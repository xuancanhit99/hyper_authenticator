import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_snapshot.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/encrypted_sync_metadata_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/encrypted_vault_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/vault_key_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/services/vault_cipher.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class EncryptedVaultSyncUseCase {
  final AuthRepository _authRepository;
  final AuthenticatorRepository _localRepository;
  final EncryptedVaultRepository _remoteRepository;
  final VaultKeyRepository _keyRepository;
  final EncryptedSyncMetadataRepository _metadataRepository;
  final VaultCipher _cipher;

  _PendingSetup? _pendingSetup;
  _PendingRecoveryKeyRotation? _pendingRecoveryKeyRotation;
  _PendingVaultKeyRotation? _pendingVaultKeyRotation;
  _PendingConflict? _pendingConflict;

  EncryptedVaultSyncUseCase(
    this._authRepository,
    this._localRepository,
    this._remoteRepository,
    this._keyRepository,
    this._metadataRepository,
    this._cipher,
  );

  Future<Either<Failure, EncryptedSyncResult>> inspect() => _run(() async {
    final userId = _requireUserId();
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null) {
      _pendingConflict = null;
      return const EncryptedSyncSetupRequired();
    }

    final dataKey = _value(await _keyRepository.read(userId));
    if (dataKey == null) {
      _pendingConflict = null;
      return EncryptedSyncRecoveryRequired(remote.updatedAt);
    }

    List<AuthenticatorAccount> remoteAccounts;
    try {
      remoteAccounts = await _cipher.decryptAccounts(
        envelope: remote.envelope,
        dataKeyBytes: dataKey,
        userId: userId,
      );
    } on VaultCryptoException {
      return EncryptedSyncRecoveryRequired(remote.updatedAt);
    }

    final localAccounts = _value(await _localRepository.getAccounts());
    final lastRevision = _metadataRepository.readLastRevision(userId);
    if (_sameSnapshot(localAccounts, remoteAccounts)) {
      await _metadataRepository.writeLastRevision(
        userId,
        remote.envelope.revision,
      );
      _pendingConflict = null;
      return _ready(userId, remote);
    }

    if (lastRevision == remote.envelope.revision) {
      _pendingConflict = null;
      return _ready(userId, remote);
    }

    _pendingConflict = _PendingConflict(
      userId: userId,
      remoteRevision: remote.envelope.revision,
    );
    return EncryptedSyncConflict(
      remoteRevision: remote.envelope.revision,
      remoteUpdatedAt: remote.updatedAt,
    );
  });

  Future<Either<Failure, EncryptedSyncResult>> prepareSetup() => _run(() async {
    final userId = _requireUserId();
    if (_value(await _remoteRepository.download(userId: userId)) != null) {
      throw const _FailureSignal(
        SyncOperationFailure(
          'Cloud vault đã tồn tại; cần recovery key thay vì tạo vault mới.',
        ),
      );
    }
    final bundle = await _cipher.createKeyBundle(userId: userId);
    _pendingSetup = _PendingSetup(userId: userId, bundle: bundle);
    _pendingRecoveryKeyRotation = null;
    _pendingVaultKeyRotation = null;
    _pendingConflict = null;
    return EncryptedSyncRecoveryKeyReady(bundle.recoveryCode);
  });

  Future<Either<Failure, EncryptedSyncResult>> confirmSetup() => _run(() async {
    final userId = _requireUserId();
    final pending = _pendingSetup;
    if (pending == null || pending.userId != userId) {
      throw const _FailureSignal(
        SyncOperationFailure('Phiên thiết lập recovery key đã hết hạn.'),
      );
    }
    if (_value(await _remoteRepository.download(userId: userId)) != null) {
      _pendingSetup = null;
      throw const _FailureSignal(
        SyncRevisionConflictFailure(
          'Cloud vault được tạo từ một thiết bị khác trong lúc thiết lập.',
        ),
      );
    }

    final localAccounts = _value(await _localRepository.getAccounts());
    final envelope = await _cipher.encryptAccounts(
      accounts: localAccounts,
      dataKeyBytes: pending.bundle.dataKeyBytes,
      userId: userId,
      revision: 1,
    );
    final publishedRevision = _value(
      await _remoteRepository.publish(
        userId: userId,
        expectedRevision: 0,
        envelope: envelope,
        wrappedDataKey: pending.bundle.wrappedDataKey,
      ),
    );
    final verified = await _verifyPublished(
      userId: userId,
      revision: publishedRevision,
      expectedEnvelope: envelope,
      expectedWrappedDataKey: pending.bundle.wrappedDataKey,
    );
    _value(await _keyRepository.write(userId, pending.bundle.dataKeyBytes));
    await _metadataRepository.writeLastRevision(userId, publishedRevision);
    await _metadataRepository.writeEnabled(userId, true);
    _pendingSetup = null;
    return EncryptedSyncCompleted(
      revision: publishedRevision,
      completedAt: verified.updatedAt,
    );
  });

  Future<Either<Failure, EncryptedSyncResult>> recover(String recoveryCode) =>
      _run(() async {
        final userId = _requireUserId();
        final remote = _value(await _remoteRepository.download(userId: userId));
        if (remote == null) {
          throw const _FailureSignal(
            SyncOperationFailure('Không có cloud vault để khôi phục.'),
          );
        }

        final dataKey = await _cipher.unwrapDataKey(
          wrappedKey: remote.wrappedDataKey,
          recoveryCode: recoveryCode.trim(),
          userId: userId,
        );
        final remoteAccounts = await _cipher.decryptAccounts(
          envelope: remote.envelope,
          dataKeyBytes: dataKey,
          userId: userId,
        );
        _value(await _keyRepository.write(userId, dataKey));

        final localAccounts = _value(await _localRepository.getAccounts());
        if (localAccounts.isNotEmpty &&
            !_sameSnapshot(localAccounts, remoteAccounts)) {
          _pendingConflict = _PendingConflict(
            userId: userId,
            remoteRevision: remote.envelope.revision,
          );
          return EncryptedSyncConflict(
            remoteRevision: remote.envelope.revision,
            remoteUpdatedAt: remote.updatedAt,
          );
        }

        _value(await _localRepository.replaceAccounts(remoteAccounts));
        await _metadataRepository.writeLastRevision(
          userId,
          remote.envelope.revision,
        );
        await _metadataRepository.writeEnabled(userId, true);
        _pendingConflict = null;
        return EncryptedSyncCompleted(
          revision: remote.envelope.revision,
          completedAt: remote.updatedAt,
        );
      });

  Future<Either<Failure, EncryptedSyncResult>> prepareRecoveryKeyRotation() =>
      _run(() async {
        final userId = _requireUserId();
        final remote = _value(await _remoteRepository.download(userId: userId));
        if (remote == null) {
          throw const _FailureSignal(
            SyncOperationFailure('Chưa có cloud vault để xoay recovery key.'),
          );
        }
        final dataKey = _value(await _keyRepository.read(userId));
        if (dataKey == null) {
          throw const _FailureSignal(
            SyncOperationFailure(
              'Thiết bị này cần recovery key hiện tại trước khi tạo key mới.',
            ),
          );
        }

        await _cipher.decryptAccounts(
          envelope: remote.envelope,
          dataKeyBytes: dataKey,
          userId: userId,
        );
        final bundle = await _cipher.createRecoveryKeyBundle(
          dataKeyBytes: dataKey,
          userId: userId,
        );
        _pendingRecoveryKeyRotation = _PendingRecoveryKeyRotation(
          userId: userId,
          remoteRevision: remote.envelope.revision,
          wrappedDataKey: bundle.wrappedDataKey,
        );
        _pendingSetup = null;
        _pendingVaultKeyRotation = null;
        _pendingConflict = null;
        return EncryptedSyncRecoveryKeyRotationReady(bundle.recoveryCode);
      });

  Future<Either<Failure, EncryptedSyncResult>>
  confirmRecoveryKeyRotation() => _run(() async {
    final userId = _requireUserId();
    final pending = _pendingRecoveryKeyRotation;
    if (pending == null || pending.userId != userId) {
      throw const _FailureSignal(
        SyncOperationFailure('Phiên xoay recovery key đã hết hạn.'),
      );
    }
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null || remote.envelope.revision != pending.remoteRevision) {
      _pendingRecoveryKeyRotation = null;
      throw const _FailureSignal(
        SyncRevisionConflictFailure(
          'Cloud vault đã thay đổi; recovery key cũ vẫn được giữ nguyên.',
        ),
      );
    }
    final dataKey = _value(await _keyRepository.read(userId));
    if (dataKey == null) {
      throw const _FailureSignal(
        SyncOperationFailure(
          'Vault key trên thiết bị không còn khả dụng; chưa thay recovery key.',
        ),
      );
    }
    final remoteAccounts = await _cipher.decryptAccounts(
      envelope: remote.envelope,
      dataKeyBytes: dataKey,
      userId: userId,
    );
    final nextRevision = remote.envelope.revision + 1;
    final envelope = await _cipher.encryptAccounts(
      accounts: remoteAccounts,
      dataKeyBytes: dataKey,
      userId: userId,
      revision: nextRevision,
    );
    late final int revision;
    try {
      revision = _value(
        await _remoteRepository.publish(
          userId: userId,
          expectedRevision: remote.envelope.revision,
          envelope: envelope,
          wrappedDataKey: pending.wrappedDataKey,
        ),
      );
    } on _FailureSignal catch (signal) {
      _pendingRecoveryKeyRotation = null;
      if (signal.failure is SyncRevisionConflictFailure) rethrow;
      throw const _FailureSignal(
        SyncOperationFailure(
          'Không xác định được recovery-key rotation đã commit hay chưa. Hãy giữ recovery key mới và kiểm tra lại cloud vault.',
        ),
      );
    }
    EncryptedVaultSnapshot verified;
    try {
      verified = await _verifyPublished(
        userId: userId,
        revision: revision,
        expectedEnvelope: envelope,
        expectedWrappedDataKey: pending.wrappedDataKey,
      );
    } on _FailureSignal {
      _pendingRecoveryKeyRotation = null;
      throw const _FailureSignal(
        SyncOperationFailure(
          'Không xác nhận được trạng thái sau khi publish. Recovery key mới có thể đã có hiệu lực; hãy giữ key mới và kiểm tra lại cloud vault.',
        ),
      );
    }
    await _metadataRepository.writeLastRevision(userId, revision);
    _pendingRecoveryKeyRotation = null;
    return EncryptedSyncCompleted(
      revision: revision,
      completedAt: verified.updatedAt,
    );
  });

  Future<Either<Failure, EncryptedSyncResult>>
  prepareVaultKeyRotation() => _run(() async {
    final userId = _requireUserId();
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null) {
      throw const _FailureSignal(
        SyncOperationFailure('Chưa có cloud vault để xoay vault key.'),
      );
    }
    final currentDataKey = _value(await _keyRepository.read(userId));
    if (currentDataKey == null) {
      throw const _FailureSignal(
        SyncOperationFailure(
          'Thiết bị này cần recovery key hiện tại trước khi xoay vault key.',
        ),
      );
    }

    await _cipher.decryptAccounts(
      envelope: remote.envelope,
      dataKeyBytes: currentDataKey,
      userId: userId,
    );
    final bundle = await _cipher.createKeyBundle(userId: userId);
    _pendingVaultKeyRotation = _PendingVaultKeyRotation(
      userId: userId,
      remoteRevision: remote.envelope.revision,
      bundle: bundle,
    );
    _pendingSetup = null;
    _pendingRecoveryKeyRotation = null;
    _pendingConflict = null;
    return EncryptedSyncVaultKeyRotationReady(bundle.recoveryCode);
  });

  Future<Either<Failure, EncryptedSyncResult>>
  confirmVaultKeyRotation() => _run(() async {
    final userId = _requireUserId();
    final pending = _pendingVaultKeyRotation;
    if (pending == null || pending.userId != userId) {
      throw const _FailureSignal(
        SyncOperationFailure('Phiên xoay vault key đã hết hạn.'),
      );
    }
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null || remote.envelope.revision != pending.remoteRevision) {
      _pendingVaultKeyRotation = null;
      throw const _FailureSignal(
        SyncRevisionConflictFailure(
          'Cloud vault đã thay đổi; vault key và recovery key cũ vẫn được giữ nguyên.',
        ),
      );
    }
    final currentDataKey = _value(await _keyRepository.read(userId));
    if (currentDataKey == null) {
      throw const _FailureSignal(
        SyncOperationFailure(
          'Vault key hiện tại không còn khả dụng; chưa xoay key.',
        ),
      );
    }
    final remoteAccounts = await _cipher.decryptAccounts(
      envelope: remote.envelope,
      dataKeyBytes: currentDataKey,
      userId: userId,
    );
    final nextRevision = remote.envelope.revision + 1;
    final envelope = await _cipher.encryptAccounts(
      accounts: remoteAccounts,
      dataKeyBytes: pending.bundle.dataKeyBytes,
      userId: userId,
      revision: nextRevision,
    );

    late final int revision;
    try {
      revision = _value(
        await _remoteRepository.publish(
          userId: userId,
          expectedRevision: remote.envelope.revision,
          envelope: envelope,
          wrappedDataKey: pending.bundle.wrappedDataKey,
        ),
      );
    } on _FailureSignal catch (signal) {
      _pendingVaultKeyRotation = null;
      if (signal.failure is SyncRevisionConflictFailure) rethrow;
      throw const _FailureSignal(
        SyncOperationFailure(
          'Không xác định được vault-key rotation đã commit hay chưa. Hãy giữ recovery key mới; thiết bị có thể cần dùng key này để khôi phục.',
        ),
      );
    }

    late final EncryptedVaultSnapshot verified;
    try {
      verified = await _verifyPublished(
        userId: userId,
        revision: revision,
        expectedEnvelope: envelope,
        expectedWrappedDataKey: pending.bundle.wrappedDataKey,
      );
      _value(await _keyRepository.write(userId, pending.bundle.dataKeyBytes));
      await _metadataRepository.writeLastRevision(userId, revision);
    } catch (_) {
      _pendingVaultKeyRotation = null;
      throw const _FailureSignal(
        SyncOperationFailure(
          'Vault key mới đã có thể được publish nhưng thiết bị chưa xác nhận hoàn tất. Hãy giữ recovery key mới và chạy recovery trước lần sync tiếp theo.',
        ),
      );
    }
    _pendingVaultKeyRotation = null;
    return EncryptedSyncCompleted(
      revision: revision,
      completedAt: verified.updatedAt,
    );
  });

  Future<Either<Failure, EncryptedSyncResult>> setEnabled(bool enabled) =>
      _run(() async {
        final userId = _requireUserId();
        await _metadataRepository.writeEnabled(userId, enabled);
        final inspected = await inspect();
        return _value(inspected);
      });

  Future<Either<Failure, EncryptedSyncResult>> sync() => _run(() async {
    final userId = _requireUserId();
    if (!_metadataRepository.readEnabled(userId)) {
      throw const _FailureSignal(
        SyncOperationFailure('Đồng bộ cloud mã hóa đầu cuối đang tắt.'),
      );
    }
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null) {
      return const EncryptedSyncSetupRequired();
    }
    final dataKey = _value(await _keyRepository.read(userId));
    if (dataKey == null) {
      return EncryptedSyncRecoveryRequired(remote.updatedAt);
    }
    final remoteAccounts = await _cipher.decryptAccounts(
      envelope: remote.envelope,
      dataKeyBytes: dataKey,
      userId: userId,
    );
    final localAccounts = _value(await _localRepository.getAccounts());
    final lastRevision = _metadataRepository.readLastRevision(userId);
    if (lastRevision != remote.envelope.revision) {
      if (_sameSnapshot(localAccounts, remoteAccounts)) {
        await _metadataRepository.writeLastRevision(
          userId,
          remote.envelope.revision,
        );
        return _ready(userId, remote);
      }
      _pendingConflict = _PendingConflict(
        userId: userId,
        remoteRevision: remote.envelope.revision,
      );
      return EncryptedSyncConflict(
        remoteRevision: remote.envelope.revision,
        remoteUpdatedAt: remote.updatedAt,
      );
    }

    if (_sameSnapshot(localAccounts, remoteAccounts)) {
      return _ready(userId, remote);
    }
    return _publishLocal(
      userId: userId,
      localAccounts: localAccounts,
      dataKey: dataKey,
      remote: remote,
    );
  });

  Future<Either<Failure, EncryptedSyncResult>> useCloud() => _run(() async {
    final userId = _requireUserId();
    final pending = _requirePendingConflict(userId);
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null || remote.envelope.revision != pending.remoteRevision) {
      _pendingConflict = null;
      throw const _FailureSignal(
        SyncRevisionConflictFailure(
          'Cloud vault tiếp tục thay đổi; hãy kiểm tra lại trước khi xử lý.',
        ),
      );
    }
    final dataKey = _value(await _keyRepository.read(userId));
    if (dataKey == null) {
      return EncryptedSyncRecoveryRequired(remote.updatedAt);
    }
    final remoteAccounts = await _cipher.decryptAccounts(
      envelope: remote.envelope,
      dataKeyBytes: dataKey,
      userId: userId,
    );
    _value(await _localRepository.replaceAccounts(remoteAccounts));
    await _metadataRepository.writeLastRevision(
      userId,
      remote.envelope.revision,
    );
    await _metadataRepository.writeEnabled(userId, true);
    _pendingConflict = null;
    return EncryptedSyncCompleted(
      revision: remote.envelope.revision,
      completedAt: remote.updatedAt,
    );
  });

  Future<Either<Failure, EncryptedSyncResult>> keepLocal() => _run(() async {
    final userId = _requireUserId();
    final pending = _requirePendingConflict(userId);
    final remote = _value(await _remoteRepository.download(userId: userId));
    if (remote == null || remote.envelope.revision != pending.remoteRevision) {
      _pendingConflict = null;
      throw const _FailureSignal(
        SyncRevisionConflictFailure(
          'Cloud vault tiếp tục thay đổi; không ghi đè dữ liệu mới.',
        ),
      );
    }
    final dataKey = _value(await _keyRepository.read(userId));
    if (dataKey == null) {
      return EncryptedSyncRecoveryRequired(remote.updatedAt);
    }
    final localAccounts = _value(await _localRepository.getAccounts());
    final completed = await _publishLocal(
      userId: userId,
      localAccounts: localAccounts,
      dataKey: dataKey,
      remote: remote,
    );
    _pendingConflict = null;
    return completed;
  });

  void cancelSensitiveOperation() {
    _pendingSetup = null;
    _pendingRecoveryKeyRotation = null;
    _pendingVaultKeyRotation = null;
    _pendingConflict = null;
  }

  Future<EncryptedSyncResult> _publishLocal({
    required String userId,
    required List<AuthenticatorAccount> localAccounts,
    required List<int> dataKey,
    required EncryptedVaultSnapshot remote,
  }) async {
    final nextRevision = remote.envelope.revision + 1;
    final envelope = await _cipher.encryptAccounts(
      accounts: localAccounts,
      dataKeyBytes: dataKey,
      userId: userId,
      revision: nextRevision,
    );
    final revision = _value(
      await _remoteRepository.publish(
        userId: userId,
        expectedRevision: remote.envelope.revision,
        envelope: envelope,
        wrappedDataKey: remote.wrappedDataKey,
      ),
    );
    final verified = await _verifyPublished(
      userId: userId,
      revision: revision,
      expectedEnvelope: envelope,
      expectedWrappedDataKey: remote.wrappedDataKey,
    );
    await _metadataRepository.writeLastRevision(userId, revision);
    return EncryptedSyncCompleted(
      revision: revision,
      completedAt: verified.updatedAt,
    );
  }

  Future<EncryptedVaultSnapshot> _verifyPublished({
    required String userId,
    required int revision,
    required EncryptedVaultEnvelope expectedEnvelope,
    required WrappedVaultKey expectedWrappedDataKey,
  }) async {
    final snapshot = _value(await _remoteRepository.download(userId: userId));
    if (snapshot == null ||
        snapshot.envelope.revision != revision ||
        snapshot.envelope != expectedEnvelope ||
        snapshot.wrappedDataKey != expectedWrappedDataKey) {
      throw const _FailureSignal(
        SyncOperationFailure(
          'Không thể verify encrypted snapshot vừa publish.',
        ),
      );
    }
    return snapshot;
  }

  EncryptedSyncReady _ready(String userId, EncryptedVaultSnapshot remote) =>
      EncryptedSyncReady(
        isEnabled: _metadataRepository.readEnabled(userId),
        revision: remote.envelope.revision,
        updatedAt: remote.updatedAt,
      );

  _PendingConflict _requirePendingConflict(String userId) {
    final pending = _pendingConflict;
    if (pending == null || pending.userId != userId) {
      throw const _FailureSignal(
        SyncOperationFailure('Sync conflict đã hết hạn; hãy kiểm tra lại.'),
      );
    }
    return pending;
  }

  String _requireUserId() {
    final userId = _authRepository.currentUserEntity?.id;
    if (userId == null || userId.trim().isEmpty) {
      throw const _FailureSignal(
        AuthCredentialsFailure('Cần đăng nhập để dùng encrypted cloud sync.'),
      );
    }
    return userId;
  }

  bool _sameSnapshot(
    List<AuthenticatorAccount> left,
    List<AuthenticatorAccount> right,
  ) {
    if (left.length != right.length) return false;
    final sortedLeft = List<AuthenticatorAccount>.from(left)
      ..sort((a, b) => a.id.compareTo(b.id));
    final sortedRight = List<AuthenticatorAccount>.from(right)
      ..sort((a, b) => a.id.compareTo(b.id));
    for (var index = 0; index < sortedLeft.length; index++) {
      if (sortedLeft[index] != sortedRight[index]) return false;
    }
    return true;
  }

  T _value<T>(Either<Failure, T> result) =>
      result.fold((failure) => throw _FailureSignal(failure), (value) => value);

  Future<Either<Failure, EncryptedSyncResult>> _run(
    Future<EncryptedSyncResult> Function() operation,
  ) async {
    try {
      return Right(await operation());
    } on _FailureSignal catch (signal) {
      return Left(signal.failure);
    } on VaultCryptoException catch (error) {
      return Left(SyncOperationFailure(error.message));
    } catch (_) {
      return const Left(
        SyncOperationFailure('Encrypted sync thất bại an toàn.'),
      );
    }
  }
}

class _PendingSetup {
  final String userId;
  final VaultKeyBundle bundle;

  const _PendingSetup({required this.userId, required this.bundle});
}

class _PendingRecoveryKeyRotation {
  final String userId;
  final int remoteRevision;
  final WrappedVaultKey wrappedDataKey;

  const _PendingRecoveryKeyRotation({
    required this.userId,
    required this.remoteRevision,
    required this.wrappedDataKey,
  });
}

class _PendingVaultKeyRotation {
  final String userId;
  final int remoteRevision;
  final VaultKeyBundle bundle;

  const _PendingVaultKeyRotation({
    required this.userId,
    required this.remoteRevision,
    required this.bundle,
  });
}

class _PendingConflict {
  final String userId;
  final int remoteRevision;

  const _PendingConflict({required this.userId, required this.remoteRevision});
}

class _FailureSignal implements Exception {
  final Failure failure;

  const _FailureSignal(this.failure);
}
