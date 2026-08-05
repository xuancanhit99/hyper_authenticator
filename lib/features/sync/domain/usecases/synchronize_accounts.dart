import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_metadata_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/cloud_account_repository.dart';
import 'package:injectable/injectable.dart';

/// Đồng bộ per-account theo nguyên tắc local-first.
///
/// Cloud/network failure không rollback mutation local. Metadata ownership ngăn
/// account đã thuộc user A bị upload tự động sang user B. Tombstone luôn thắng
/// update offline để thao tác xóa không bị một thiết bị cũ làm sống lại.
abstract class AccountSynchronizer {
  Future<Either<Failure, AccountSyncResult>> call();
}

@LazySingleton(as: AccountSynchronizer)
class SynchronizeAccounts implements AccountSynchronizer {
  SynchronizeAccounts(
    this._authRepository,
    this._local,
    this._remote,
    this._metadataStore,
  );

  final AuthRepository _authRepository;
  final AuthenticatorRepository _local;
  final CloudAccountRepository _remote;
  final AccountSyncMetadataRepository _metadataStore;
  final Sha256 _sha256 = Sha256();

  Future<void> _operationTail = Future<void>.value();

  @override
  Future<Either<Failure, AccountSyncResult>> call() {
    final completer = Completer<Either<Failure, AccountSyncResult>>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(Right(await _synchronize()));
      } on AccountSyncMetadataException {
        completer.complete(
          const Left(
            SyncOperationFailure(
              'Metadata đồng bộ local bị lỗi; đã dừng để tránh trộn dữ liệu giữa các tài khoản.',
            ),
          ),
        );
      } on _FailureSignal catch (signal) {
        completer.complete(Left(signal.failure));
      } on ServerException {
        completer.complete(
          const Left(
            SyncOperationFailure(
              'Cloud sync tạm thời không khả dụng; thay đổi local sẽ tự thử lại.',
            ),
          ),
        );
      } catch (_) {
        completer.complete(
          const Left(
            SyncOperationFailure(
              'Cloud sync thất bại an toàn; không có TOTP secret nào bị ghi vào log.',
            ),
          ),
        );
      }
    });
    return completer.future;
  }

  Future<AccountSyncResult> _synchronize() async {
    final user = _authRepository.currentUserEntity;
    if (user == null) return const AccountSyncSignedOut();
    final userId = user.id;

    final metadata = (await _metadataStore.read()).mutableCopy();
    final localAccounts = _value(await _local.getAccounts());
    final localById = <String, AuthenticatorAccount>{
      for (final account in localAccounts) account.id: account,
    };

    // Bind account chưa có owner trước mọi network call. Nếu lần upload đầu của
    // user A mất mạng rồi user chuyển sang B, metadata đã persist này ngăn mã
    // local bị user B nhận nhầm.
    var ownershipChanged = false;
    for (final account in localAccounts) {
      if (!metadata.records.containsKey(account.id)) {
        metadata.records[account.id] = SyncedAccountMetadata(
          ownerUserId: userId,
          remoteRevision: 0,
          syncedFingerprint: null,
          isDeleted: false,
        );
        ownershipChanged = true;
      }
    }
    if (ownershipChanged) {
      await _metadataStore.write(metadata);
    }

    final remoteRecords = await _remote.list(userId: userId);
    final remoteById = <String, CloudAccountRecord>{};
    for (final record in remoteRecords) {
      if (remoteById.containsKey(record.accountId)) {
        throw const FormatException('Duplicate cloud account ID.');
      }
      remoteById[record.accountId] = record;
    }

    var uploadedCount = 0;
    var downloadedCount = 0;
    var deletedCount = 0;

    // Tombstone là deletion intent bền vững và luôn thắng update offline.
    for (final remoteRecord in remoteRecords.where((row) => row.isDeleted)) {
      final existingMetadata = metadata.records[remoteRecord.accountId];
      if (existingMetadata != null && existingMetadata.ownerUserId != userId) {
        continue;
      }
      if (localById.remove(remoteRecord.accountId) != null) {
        await _deleteLocalIfPresent(remoteRecord.accountId);
        deletedCount++;
      }
      metadata.records[remoteRecord.accountId] = SyncedAccountMetadata(
        ownerUserId: userId,
        remoteRevision: remoteRecord.revision,
        syncedFingerprint: null,
        isDeleted: true,
      );
    }

    // Áp remote live record lên local sạch hoặc thiết bị mới. Local dirty được
    // giữ lại để push ở pha sau.
    for (final remoteRecord in remoteRecords.where((row) => !row.isDeleted)) {
      final remoteAccount = remoteRecord.account!;
      final existingMetadata = metadata.records[remoteRecord.accountId];
      if (existingMetadata != null && existingMetadata.ownerUserId != userId) {
        continue;
      }
      final localAccount = localById[remoteRecord.accountId];
      final remoteFingerprint = await _fingerprint(remoteAccount);

      if (localAccount == null) {
        if (existingMetadata != null && !existingMetadata.isDeleted) {
          // Metadata tồn tại nhưng local không còn: đây là delete local đang
          // chờ đẩy lên cloud, không phải thiết bị mới.
          continue;
        }
        _value(await _local.saveAccount(remoteAccount));
        localById[remoteAccount.id] = remoteAccount;
        metadata.records[remoteAccount.id] = SyncedAccountMetadata(
          ownerUserId: userId,
          remoteRevision: remoteRecord.revision,
          syncedFingerprint: remoteFingerprint,
          isDeleted: false,
        );
        downloadedCount++;
        continue;
      }

      final localFingerprint = await _fingerprint(localAccount);
      if (existingMetadata == null) {
        // Stable UUID trùng nhau biểu thị cùng logical record. Nếu payload bằng
        // nhau, chỉ bind ownership; nếu khác, local sẽ thắng ở pha push.
        metadata.records[localAccount.id] = SyncedAccountMetadata(
          ownerUserId: userId,
          remoteRevision: remoteRecord.revision,
          syncedFingerprint: localFingerprint == remoteFingerprint
              ? remoteFingerprint
              : null,
          isDeleted: false,
        );
      } else if (localFingerprint == existingMetadata.syncedFingerprint &&
          (existingMetadata.remoteRevision < remoteRecord.revision ||
              localFingerprint != remoteFingerprint)) {
        _value(await _local.saveAccount(remoteAccount));
        localById[remoteAccount.id] = remoteAccount;
        metadata.records[remoteAccount.id] = existingMetadata.copyWith(
          remoteRevision: remoteRecord.revision,
          syncedFingerprint: remoteFingerprint,
          isDeleted: false,
        );
        downloadedCount++;
      }
    }

    // Push create/update. CAS conflict được refresh rồi retry một lần; delete
    // remote xuất hiện trong lúc retry vẫn thắng và xóa local.
    for (final account in List<AuthenticatorAccount>.from(localById.values)) {
      var recordMetadata = metadata.records[account.id]!;
      if (recordMetadata.ownerUserId != userId) continue;
      final fingerprint = await _fingerprint(account);
      if (!recordMetadata.isDeleted &&
          recordMetadata.syncedFingerprint == fingerprint) {
        continue;
      }

      var expectedRevision =
          remoteById[account.id]?.revision ?? recordMetadata.remoteRevision;
      CloudAccountRecord published;
      try {
        published = await _remote.upsert(
          userId: userId,
          account: account,
          expectedRevision: expectedRevision,
        );
      } on CloudAccountRevisionConflictException {
        final latest = await _findRemote(userId, account.id);
        if (latest?.isDeleted == true) {
          await _deleteLocalIfPresent(account.id);
          localById.remove(account.id);
          metadata.records[account.id] = SyncedAccountMetadata(
            ownerUserId: userId,
            remoteRevision: latest!.revision,
            syncedFingerprint: null,
            isDeleted: true,
          );
          deletedCount++;
          continue;
        }
        expectedRevision = latest?.revision ?? 0;
        published = await _remote.upsert(
          userId: userId,
          account: account,
          expectedRevision: expectedRevision,
        );
      } on CloudAccountTombstonedException {
        final latest = await _findRemote(userId, account.id);
        await _deleteLocalIfPresent(account.id);
        localById.remove(account.id);
        metadata.records[account.id] = SyncedAccountMetadata(
          ownerUserId: userId,
          remoteRevision: latest?.revision ?? expectedRevision,
          syncedFingerprint: null,
          isDeleted: true,
        );
        deletedCount++;
        continue;
      }
      recordMetadata = SyncedAccountMetadata(
        ownerUserId: userId,
        remoteRevision: published.revision,
        syncedFingerprint: fingerprint,
        isDeleted: false,
      );
      metadata.records[account.id] = recordMetadata;
      remoteById[account.id] = published;
      uploadedCount++;
    }

    // Metadata có live record nhưng local đã biến mất là local delete intent.
    for (final entry in List<MapEntry<String, SyncedAccountMetadata>>.from(
      metadata.records.entries,
    )) {
      final accountId = entry.key;
      var recordMetadata = entry.value;
      if (recordMetadata.ownerUserId != userId ||
          recordMetadata.isDeleted ||
          localById.containsKey(accountId)) {
        continue;
      }
      final remoteRecord = remoteById[accountId];
      if (remoteRecord == null && recordMetadata.remoteRevision == 0) {
        metadata.records.remove(accountId);
        continue;
      }
      CloudAccountRecord deleted;
      try {
        deleted = await _remote.delete(
          userId: userId,
          accountId: accountId,
          expectedRevision:
              remoteRecord?.revision ?? recordMetadata.remoteRevision,
        );
      } on CloudAccountRevisionConflictException {
        final latest = await _findRemote(userId, accountId);
        if (latest == null) {
          metadata.records.remove(accountId);
          continue;
        }
        if (latest.isDeleted) {
          deleted = latest;
        } else {
          deleted = await _remote.delete(
            userId: userId,
            accountId: accountId,
            expectedRevision: latest.revision,
          );
        }
      }
      recordMetadata = recordMetadata.copyWith(
        remoteRevision: deleted.revision,
        clearSyncedFingerprint: true,
        isDeleted: true,
      );
      metadata.records[accountId] = recordMetadata;
      deletedCount++;
    }

    await _metadataStore.write(metadata);
    return AccountSyncCompleted(
      completedAt: DateTime.now().toUtc(),
      uploadedCount: uploadedCount,
      downloadedCount: downloadedCount,
      deletedCount: deletedCount,
    );
  }

  Future<CloudAccountRecord?> _findRemote(
    String userId,
    String accountId,
  ) async {
    final records = await _remote.list(userId: userId);
    for (final record in records) {
      if (record.accountId == accountId) return record;
    }
    return null;
  }

  Future<void> _deleteLocalIfPresent(String accountId) async {
    final result = await _local.deleteAccount(accountId);
    result.fold((failure) {
      if (failure is! AccountNotFoundFailure) throw _FailureSignal(failure);
    }, (_) {});
  }

  T _value<T>(Either<Failure, T> either) =>
      either.fold((failure) => throw _FailureSignal(failure), (value) => value);

  Future<String> _fingerprint(AuthenticatorAccount account) async {
    final canonical = jsonEncode({
      'id': account.id,
      'issuer': account.issuer,
      'accountName': account.accountName,
      'secretKey': account.secretKey,
      'algorithm': account.algorithm,
      'digits': account.digits,
      'period': account.period,
    });
    final hash = await _sha256.hash(utf8.encode(canonical));
    return base64UrlEncode(hash.bytes);
  }
}

class _FailureSignal implements Exception {
  const _FailureSignal(this.failure);

  final Failure failure;
}
