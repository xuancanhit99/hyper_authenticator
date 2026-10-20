import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/local_vault_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/account_payload_validator.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';
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
  SynchronizeAccounts(this._authRepository, this._local, this._remote);

  final AuthRepository _authRepository;
  final LocalVaultRepository _local;
  final CloudAccountRepository _remote;
  final Sha256 _sha256 = Sha256();

  Future<void> _operationTail = Future<void>.value();

  @override
  Future<Either<Failure, AccountSyncResult>> call() {
    final completer = Completer<Either<Failure, AccountSyncResult>>();
    _operationTail = _operationTail.then((_) async {
      try {
        AccountSyncResult? result;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            result = await _synchronize();
            break;
          } on LocalVaultConflict {
            if (attempt == 2) rethrow;
          }
        }
        completer.complete(Right(result!));
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

    var changedSession = false;
    final subscription = _authRepository.authEntityChanges.listen((next) {
      if (next?.id != userId) changedSession = true;
    });
    bool canCommit() =>
        !changedSession && _authRepository.currentUserEntity?.id == userId;
    try {
      return await _synchronizeUser(
        userId,
        _GuardedCloudRepository(_remote, canCommit),
        canCommit,
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<AccountSyncResult> _synchronizeUser(
    String userId,
    CloudAccountRepository remote,
    bool Function() canCommit,
  ) async {
    final snapshot = await _local.readVault();
    var generation = snapshot.generation;
    final metadata = snapshot.metadata.mutableCopy();
    final deleteIntents = Set<String>.of(snapshot.deletedAccountIds);
    final localAccounts = snapshot.accounts;
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
      generation = await _local.commitVault(
        expectedGeneration: generation,
        accounts: localAccounts,
        metadata: metadata,
        deletedAccountIds: deleteIntents,
        canCommit: canCommit,
      );
    }

    final remoteRecords = await remote.list(userId: userId);
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
    final blockedAccountIds = <String>{
      for (final record in remoteRecords)
        if (record.isBlocked &&
            (metadata.records[record.accountId] == null ||
                metadata.records[record.accountId]!.ownerUserId == userId))
          record.accountId,
    };

    // Tombstone là deletion intent bền vững và luôn thắng update offline.
    for (final remoteRecord in remoteRecords.where((row) => row.isDeleted)) {
      final existingMetadata = metadata.records[remoteRecord.accountId];
      if (existingMetadata != null && existingMetadata.ownerUserId != userId) {
        continue;
      }
      if (localById.remove(remoteRecord.accountId) != null) {
        deletedCount++;
      }
      deleteIntents.remove(remoteRecord.accountId);
      metadata.records[remoteRecord.accountId] = SyncedAccountMetadata(
        ownerUserId: userId,
        remoteRevision: remoteRecord.revision,
        syncedFingerprint: null,
        isDeleted: true,
      );
    }

    // Áp remote live record lên local sạch hoặc thiết bị mới. Local dirty được
    // giữ lại để push ở pha sau.
    for (final remoteRecord in remoteRecords.where(
      (row) => !row.isDeleted && !row.isBlocked,
    )) {
      final remoteAccount = remoteRecord.account!;
      final existingMetadata = metadata.records[remoteRecord.accountId];
      if (existingMetadata != null && existingMetadata.ownerUserId != userId) {
        continue;
      }
      final localAccount = localById[remoteRecord.accountId];
      final remoteFingerprint = await _fingerprint(remoteAccount);

      if (localAccount == null) {
        if (deleteIntents.contains(remoteAccount.id)) {
          // Metadata tồn tại nhưng local không còn: đây là delete local đang
          // chờ đẩy lên cloud, không phải thiết bị mới.
          continue;
        }
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
      try {
        AccountPayloadValidator.validateCloudAccount(account);
      } on FormatException {
        // Legacy data stays local and retains ownership/pending intent. Only a
        // known permanent payload rejection is isolated; network/auth failures
        // still abort the cycle through the existing failure boundary.
        blockedAccountIds.add(account.id);
        continue;
      }
      final fingerprint = await _fingerprint(account);
      if (!recordMetadata.isDeleted &&
          recordMetadata.syncedFingerprint == fingerprint) {
        continue;
      }

      var expectedRevision =
          remoteById[account.id]?.revision ?? recordMetadata.remoteRevision;
      CloudAccountRecord published;
      try {
        published = await remote.upsert(
          userId: userId,
          account: account,
          expectedRevision: expectedRevision,
        );
      } on CloudAccountRevisionConflictException {
        final latest = await _findRemote(remote, userId, account.id);
        if (latest?.isDeleted == true) {
          deleteIntents.remove(account.id);
          localById.remove(account.id);
          metadata.records[account.id] = SyncedAccountMetadata(
            ownerUserId: userId,
            remoteRevision: latest!.revision,
            syncedFingerprint: null,
            isDeleted: true,
          );
          blockedAccountIds.remove(account.id);
          deletedCount++;
          continue;
        }
        expectedRevision = latest?.revision ?? 0;
        published = await remote.upsert(
          userId: userId,
          account: account,
          expectedRevision: expectedRevision,
        );
      } on CloudAccountTombstonedException {
        final latest = await _findRemote(remote, userId, account.id);
        deleteIntents.remove(account.id);
        localById.remove(account.id);
        metadata.records[account.id] = SyncedAccountMetadata(
          ownerUserId: userId,
          remoteRevision: latest?.revision ?? expectedRevision,
          syncedFingerprint: null,
          isDeleted: true,
        );
        blockedAccountIds.remove(account.id);
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
      blockedAccountIds.remove(account.id);
      uploadedCount++;
    }

    // Only a durable, explicit local deletion may publish a tombstone.
    for (final entry in List<MapEntry<String, SyncedAccountMetadata>>.from(
      metadata.records.entries,
    )) {
      final accountId = entry.key;
      var recordMetadata = entry.value;
      if (recordMetadata.ownerUserId != userId ||
          recordMetadata.isDeleted ||
          !deleteIntents.contains(accountId) ||
          localById.containsKey(accountId)) {
        continue;
      }
      final remoteRecord = remoteById[accountId];
      CloudAccountRecord deleted;
      try {
        deleted = await remote.delete(
          userId: userId,
          accountId: accountId,
          expectedRevision:
              remoteRecord?.revision ?? recordMetadata.remoteRevision,
        );
      } on CloudAccountRevisionConflictException {
        final latest = await _findRemote(remote, userId, accountId);
        if (latest == null) {
          deleted = await remote.delete(
            userId: userId,
            accountId: accountId,
            expectedRevision: 0,
          );
        } else if (latest.isDeleted) {
          deleted = latest;
        } else {
          deleted = await remote.delete(
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
      deleteIntents.remove(accountId);
      blockedAccountIds.remove(accountId);
      deletedCount++;
    }

    await _local.commitVault(
      expectedGeneration: generation,
      accounts: localById.values.toList(),
      metadata: metadata,
      deletedAccountIds: deleteIntents,
      canCommit: canCommit,
    );
    return AccountSyncCompleted(
      completedAt: DateTime.now().toUtc(),
      uploadedCount: uploadedCount,
      downloadedCount: downloadedCount,
      deletedCount: deletedCount,
      blockedAccountCount: blockedAccountIds.length,
    );
  }

  Future<CloudAccountRecord?> _findRemote(
    CloudAccountRepository remote,
    String userId,
    String accountId,
  ) async {
    final records = await remote.list(userId: userId);
    for (final record in records) {
      if (record.accountId == accountId) return record;
    }
    return null;
  }

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

class _GuardedCloudRepository implements CloudAccountRepository {
  _GuardedCloudRepository(this.inner, this.canContinue);
  final CloudAccountRepository inner;
  final bool Function() canContinue;
  Future<T> _checked<T>(Future<T> Function() action) async {
    if (!canContinue()) {
      throw const _FailureSignal(
        SyncOperationFailure('Phiên đăng nhập đã thay đổi; đã dừng đồng bộ.'),
      );
    }
    final value = await action();
    if (!canContinue()) {
      throw const _FailureSignal(
        SyncOperationFailure('Phiên đăng nhập đã thay đổi; đã dừng đồng bộ.'),
      );
    }
    return value;
  }

  @override
  Future<List<CloudAccountRecord>> list({required String userId}) =>
      _checked(() => inner.list(userId: userId));
  @override
  Future<CloudAccountRecord> upsert({
    required String userId,
    required AuthenticatorAccount account,
    required int expectedRevision,
  }) => _checked(
    () => inner.upsert(
      userId: userId,
      account: account,
      expectedRevision: expectedRevision,
    ),
  );
  @override
  Future<CloudAccountRecord> delete({
    required String userId,
    required String accountId,
    required int expectedRevision,
  }) => _checked(
    () => inner.delete(
      userId: userId,
      accountId: accountId,
      expectedRevision: expectedRevision,
    ),
  );
}
