import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
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
import 'package:hyper_authenticator/features/sync/domain/usecases/encrypted_vault_sync_usecase.dart';

void main() {
  const userId = '00000000-0000-4000-8000-000000000001';
  const first = AuthenticatorAccount(
    id: '11111111-1111-4111-8111-111111111111',
    issuer: 'TEST_ONLY Issuer A',
    accountName: 'a@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP',
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
  );
  const second = AuthenticatorAccount(
    id: '22222222-2222-4222-8222-222222222222',
    issuer: 'TEST_ONLY Issuer B',
    accountName: 'b@example.invalid',
    secretKey: 'KRSXG5DSNFXGOIDB',
    algorithm: 'SHA256',
    digits: 8,
    period: 45,
  );

  late VaultCipher cipher;
  late _MemoryEncryptedVaultRepository remote;
  late _MemoryAuthenticatorRepository local;
  late _MemoryVaultKeyRepository keys;
  late _MemoryMetadataRepository metadata;
  late EncryptedVaultSyncUseCase useCase;

  setUp(() {
    cipher = VaultCipher();
    remote = _MemoryEncryptedVaultRepository();
    local = _MemoryAuthenticatorRepository([first]);
    keys = _MemoryVaultKeyRepository();
    metadata = _MemoryMetadataRepository();
    useCase = _createUseCase(
      userId: userId,
      cipher: cipher,
      remote: remote,
      local: local,
      keys: keys,
      metadata: metadata,
    );
  });

  Future<String> seedRemote(List<AuthenticatorAccount> accounts) async {
    local.accounts
      ..clear()
      ..addAll(accounts);
    final prepared = _right(await useCase.prepareSetup());
    final recoveryCode =
        (prepared as EncryptedSyncRecoveryKeyReady).recoveryCode;
    _right(await useCase.confirmSetup());
    return recoveryCode;
  }

  test('setup chỉ persist DEK sau confirm và publish revision 1', () async {
    expect(_right(await useCase.inspect()), isA<EncryptedSyncSetupRequired>());

    final prepared = _right(await useCase.prepareSetup());
    expect(prepared, isA<EncryptedSyncRecoveryKeyReady>());
    expect(keys.values, isEmpty);
    expect(remote.snapshot, isNull);

    final completed = _right(await useCase.confirmSetup());
    expect(completed, isA<EncryptedSyncCompleted>());
    expect(remote.snapshot?.envelope.revision, 1);
    expect(keys.values[userId], isNotNull);
    expect(metadata.revisions[userId], 1);
    expect(metadata.enabled[userId], isTrue);

    final decrypted = await cipher.decryptAccounts(
      envelope: remote.snapshot!.envelope,
      dataKeyBytes: keys.values[userId]!,
      userId: userId,
    );
    expect(decrypted, [first]);
  });

  test('hủy setup không tạo remote snapshot hoặc persist key', () async {
    await useCase.prepareSetup();
    useCase.cancelSensitiveOperation();

    final result = await useCase.confirmSetup();
    expect(result.isLeft(), isTrue);
    expect(remote.snapshot, isNull);
    expect(keys.values, isEmpty);
  });

  test('xoay recovery key publish revision mới và vô hiệu key cũ', () async {
    final oldRecoveryCode = await seedRemote([first, second]);
    final dataKey = List<int>.from(keys.values[userId]!);
    final oldWrappedKey = remote.snapshot!.wrappedDataKey;

    final prepared = _right(await useCase.prepareRecoveryKeyRotation());
    expect(prepared, isA<EncryptedSyncRecoveryKeyRotationReady>());
    final newRecoveryCode =
        (prepared as EncryptedSyncRecoveryKeyRotationReady).recoveryCode;
    expect(newRecoveryCode, isNot(oldRecoveryCode));
    expect(remote.snapshot!.envelope.revision, 1);
    expect(remote.snapshot!.wrappedDataKey, oldWrappedKey);

    final completed = _right(await useCase.confirmRecoveryKeyRotation());
    expect(completed, isA<EncryptedSyncCompleted>());
    expect(remote.snapshot!.envelope.revision, 2);
    expect(remote.snapshot!.wrappedDataKey, isNot(oldWrappedKey));
    expect(metadata.revisions[userId], 2);
    expect(keys.values[userId], dataKey);

    await expectLater(
      cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: oldRecoveryCode,
        userId: userId,
      ),
      throwsA(isA<VaultCryptoException>()),
    );
    final recoveredDataKey = await cipher.unwrapDataKey(
      wrappedKey: remote.snapshot!.wrappedDataKey,
      recoveryCode: newRecoveryCode,
      userId: userId,
    );
    expect(recoveredDataKey, dataKey);
    expect(
      await cipher.decryptAccounts(
        envelope: remote.snapshot!.envelope,
        dataKeyBytes: recoveredDataKey,
        userId: userId,
      ),
      [first, second],
    );
  });

  test('hủy xoay recovery key giữ nguyên remote và key cũ', () async {
    final oldRecoveryCode = await seedRemote([first]);
    final oldSnapshot = remote.snapshot!;

    _right(await useCase.prepareRecoveryKeyRotation());
    useCase.cancelSensitiveOperation();

    final result = await useCase.confirmRecoveryKeyRotation();
    expect(result.isLeft(), isTrue);
    expect(remote.snapshot, same(oldSnapshot));
    final recoveredDataKey = await cipher.unwrapDataKey(
      wrappedKey: remote.snapshot!.wrappedDataKey,
      recoveryCode: oldRecoveryCode,
      userId: userId,
    );
    expect(recoveredDataKey, keys.values[userId]);
  });

  test(
    'conflict khi xoay key không ghi đè revision mới từ thiết bị khác',
    () async {
      final oldRecoveryCode = await seedRemote([first]);
      final dataKey = keys.values[userId]!;
      final oldWrappedKey = remote.snapshot!.wrappedDataKey;
      final prepared = _right(await useCase.prepareRecoveryKeyRotation());
      final unusedNewRecoveryCode =
          (prepared as EncryptedSyncRecoveryKeyRotationReady).recoveryCode;
      final concurrentEnvelope = await cipher.encryptAccounts(
        accounts: const [second],
        dataKeyBytes: dataKey,
        userId: userId,
        revision: 2,
      );
      await remote.publish(
        userId: userId,
        expectedRevision: 1,
        envelope: concurrentEnvelope,
        wrappedDataKey: oldWrappedKey,
      );

      final result = await useCase.confirmRecoveryKeyRotation();

      expect(
        result.fold((failure) => failure, (_) => null),
        isA<SyncRevisionConflictFailure>(),
      );
      expect(remote.snapshot!.envelope.revision, 2);
      expect(remote.snapshot!.wrappedDataKey, oldWrappedKey);
      expect(
        await cipher.unwrapDataKey(
          wrappedKey: remote.snapshot!.wrappedDataKey,
          recoveryCode: oldRecoveryCode,
          userId: userId,
        ),
        dataKey,
      );
      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: remote.snapshot!.wrappedDataKey,
          recoveryCode: unusedNewRecoveryCode,
          userId: userId,
        ),
        throwsA(isA<VaultCryptoException>()),
      );
    },
  );

  test('verify lỗi sau publish cảnh báo key mới có thể đã hiệu lực', () async {
    final oldRecoveryCode = await seedRemote([first]);
    final prepared = _right(await useCase.prepareRecoveryKeyRotation());
    final newRecoveryCode =
        (prepared as EncryptedSyncRecoveryKeyRotationReady).recoveryCode;
    remote.tamperNextDownloadAfterPublish = true;

    final result = await useCase.confirmRecoveryKeyRotation();

    final failure = result.fold((value) => value, (_) => null);
    expect(failure, isA<SyncOperationFailure>());
    expect(failure?.message, contains('có thể đã có hiệu lực'));
    expect(remote.snapshot!.envelope.revision, 2);
    expect(metadata.revisions[userId], 1);
    await expectLater(
      cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: oldRecoveryCode,
        userId: userId,
      ),
      throwsA(isA<VaultCryptoException>()),
    );
    expect(
      await cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: newRecoveryCode,
        userId: userId,
      ),
      keys.values[userId],
    );
  });

  test(
    'transport lỗi sau recovery-key commit được báo là trạng thái mơ hồ',
    () async {
      final oldRecoveryCode = await seedRemote([first]);
      final prepared = _right(await useCase.prepareRecoveryKeyRotation());
      final newRecoveryCode =
          (prepared as EncryptedSyncRecoveryKeyRotationReady).recoveryCode;
      remote.failNextPublishAfterCommit = true;

      final result = await useCase.confirmRecoveryKeyRotation();

      final failure = result.fold((value) => value, (_) => null);
      expect(failure, isA<SyncOperationFailure>());
      expect(failure?.message, contains('đã commit hay chưa'));
      expect(remote.snapshot!.envelope.revision, 2);
      expect(metadata.revisions[userId], 1);
      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: remote.snapshot!.wrappedDataKey,
          recoveryCode: oldRecoveryCode,
          userId: userId,
        ),
        throwsA(isA<VaultCryptoException>()),
      );
      expect(
        await cipher.unwrapDataKey(
          wrappedKey: remote.snapshot!.wrappedDataKey,
          recoveryCode: newRecoveryCode,
          userId: userId,
        ),
        keys.values[userId],
      );
    },
  );

  test(
    'xoay vault key thay DEK và buộc thiết bị giữ key cũ recovery lại',
    () async {
      final oldRecoveryCode = await seedRemote([first, second]);
      final oldDataKey = List<int>.from(keys.values[userId]!);
      final oldWrappedKey = remote.snapshot!.wrappedDataKey;

      final prepared = _right(await useCase.prepareVaultKeyRotation());
      expect(prepared, isA<EncryptedSyncVaultKeyRotationReady>());
      final newRecoveryCode =
          (prepared as EncryptedSyncVaultKeyRotationReady).recoveryCode;

      final completed = _right(await useCase.confirmVaultKeyRotation());

      expect(completed, isA<EncryptedSyncCompleted>());
      expect(remote.snapshot!.envelope.revision, 2);
      expect(remote.snapshot!.wrappedDataKey, isNot(oldWrappedKey));
      expect(keys.values[userId], isNot(oldDataKey));
      expect(metadata.revisions[userId], 2);
      await expectLater(
        cipher.decryptAccounts(
          envelope: remote.snapshot!.envelope,
          dataKeyBytes: oldDataKey,
          userId: userId,
        ),
        throwsA(isA<VaultCryptoException>()),
      );
      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: remote.snapshot!.wrappedDataKey,
          recoveryCode: oldRecoveryCode,
          userId: userId,
        ),
        throwsA(isA<VaultCryptoException>()),
      );
      final newDataKey = await cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: newRecoveryCode,
        userId: userId,
      );
      expect(newDataKey, keys.values[userId]);
      expect(
        await cipher.decryptAccounts(
          envelope: remote.snapshot!.envelope,
          dataKeyBytes: newDataKey,
          userId: userId,
        ),
        [first, second],
      );

      final staleDeviceKeys = _MemoryVaultKeyRepository()
        ..values[userId] = oldDataKey;
      final staleDevice = _createUseCase(
        userId: userId,
        cipher: cipher,
        remote: remote,
        local: _MemoryAuthenticatorRepository(const [first, second]),
        keys: staleDeviceKeys,
        metadata: _MemoryMetadataRepository(),
      );
      expect(
        _right(await staleDevice.inspect()),
        isA<EncryptedSyncRecoveryRequired>(),
      );
    },
  );

  test('hủy xoay vault key giữ nguyên DEK, recovery key và remote', () async {
    final oldRecoveryCode = await seedRemote([first]);
    final oldDataKey = List<int>.from(keys.values[userId]!);
    final oldSnapshot = remote.snapshot!;

    _right(await useCase.prepareVaultKeyRotation());
    useCase.cancelSensitiveOperation();

    final result = await useCase.confirmVaultKeyRotation();
    expect(result.isLeft(), isTrue);
    expect(remote.snapshot, same(oldSnapshot));
    expect(keys.values[userId], oldDataKey);
    expect(
      await cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: oldRecoveryCode,
        userId: userId,
      ),
      oldDataKey,
    );
  });

  test(
    'conflict khi xoay vault key không thay key local hoặc cloud mới',
    () async {
      await seedRemote([first]);
      final oldDataKey = List<int>.from(keys.values[userId]!);
      final oldWrappedKey = remote.snapshot!.wrappedDataKey;
      _right(await useCase.prepareVaultKeyRotation());
      final concurrentEnvelope = await cipher.encryptAccounts(
        accounts: const [second],
        dataKeyBytes: oldDataKey,
        userId: userId,
        revision: 2,
      );
      await remote.publish(
        userId: userId,
        expectedRevision: 1,
        envelope: concurrentEnvelope,
        wrappedDataKey: oldWrappedKey,
      );

      final result = await useCase.confirmVaultKeyRotation();

      expect(
        result.fold((failure) => failure, (_) => null),
        isA<SyncRevisionConflictFailure>(),
      );
      expect(remote.snapshot!.envelope, concurrentEnvelope);
      expect(remote.snapshot!.wrappedDataKey, oldWrappedKey);
      expect(keys.values[userId], oldDataKey);
    },
  );

  test(
    'verify lỗi sau vault-key publish giữ DEK cũ và yêu cầu giữ key mới',
    () async {
      await seedRemote([first]);
      final oldDataKey = List<int>.from(keys.values[userId]!);
      final prepared = _right(await useCase.prepareVaultKeyRotation());
      final newRecoveryCode =
          (prepared as EncryptedSyncVaultKeyRotationReady).recoveryCode;
      remote.tamperNextDownloadAfterPublish = true;

      final result = await useCase.confirmVaultKeyRotation();

      final failure = result.fold((value) => value, (_) => null);
      expect(failure, isA<SyncOperationFailure>());
      expect(failure?.message, contains('giữ recovery key mới'));
      expect(remote.snapshot!.envelope.revision, 2);
      expect(keys.values[userId], oldDataKey);
      expect(metadata.revisions[userId], 1);
      final newDataKey = await cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: newRecoveryCode,
        userId: userId,
      );
      expect(newDataKey, isNot(oldDataKey));
    },
  );

  test(
    'transport lỗi sau vault-key commit giữ DEK cũ và recovery key mới',
    () async {
      await seedRemote([first]);
      final oldDataKey = List<int>.from(keys.values[userId]!);
      final prepared = _right(await useCase.prepareVaultKeyRotation());
      final newRecoveryCode =
          (prepared as EncryptedSyncVaultKeyRotationReady).recoveryCode;
      remote.failNextPublishAfterCommit = true;

      final result = await useCase.confirmVaultKeyRotation();

      final failure = result.fold((value) => value, (_) => null);
      expect(failure, isA<SyncOperationFailure>());
      expect(failure?.message, contains('đã commit hay chưa'));
      expect(remote.snapshot!.envelope.revision, 2);
      expect(keys.values[userId], oldDataKey);
      expect(metadata.revisions[userId], 1);
      final newDataKey = await cipher.unwrapDataKey(
        wrappedKey: remote.snapshot!.wrappedDataKey,
        recoveryCode: newRecoveryCode,
        userId: userId,
      );
      expect(newDataKey, isNot(oldDataKey));
      expect(
        await cipher.decryptAccounts(
          envelope: remote.snapshot!.envelope,
          dataKeyBytes: newDataKey,
          userId: userId,
        ),
        [first],
      );
    },
  );

  test(
    'lỗi persist DEK sau vault-key publish giữ recovery path rõ ràng',
    () async {
      await seedRemote([first]);
      final oldDataKey = List<int>.from(keys.values[userId]!);
      final prepared = _right(await useCase.prepareVaultKeyRotation());
      final newRecoveryCode =
          (prepared as EncryptedSyncVaultKeyRotationReady).recoveryCode;
      keys.failNextWrite = true;

      final result = await useCase.confirmVaultKeyRotation();

      final failure = result.fold((value) => value, (_) => null);
      expect(failure, isA<SyncOperationFailure>());
      expect(failure?.message, contains('chạy recovery'));
      expect(remote.snapshot!.envelope.revision, 2);
      expect(keys.values[userId], oldDataKey);
      expect(metadata.revisions[userId], 1);
      expect(
        await cipher.unwrapDataKey(
          wrappedKey: remote.snapshot!.wrappedDataKey,
          recoveryCode: newRecoveryCode,
          userId: userId,
        ),
        isNot(oldDataKey),
      );
    },
  );

  test(
    'recovery trên thiết bị mới decrypt rồi atomically replace local',
    () async {
      final recoveryCode = await seedRemote([first, second]);
      local.accounts.clear();
      keys.values.clear();
      metadata.clear();

      final inspected = _right(await useCase.inspect());
      expect(inspected, isA<EncryptedSyncRecoveryRequired>());
      final recovered = _right(await useCase.recover(recoveryCode));

      expect(recovered, isA<EncryptedSyncCompleted>());
      expect(local.accounts, [first, second]);
      expect(local.replaceCount, 1);
      expect(metadata.revisions[userId], 1);
    },
  );

  test('recovery key sai không thay key hoặc local vault', () async {
    await seedRemote([first]);
    keys.values.clear();
    metadata.clear();
    local.accounts
      ..clear()
      ..add(second);

    final result = await useCase.recover('HA1-TEST_ONLY_INVALID');

    expect(result.isLeft(), isTrue);
    expect(local.accounts, [second]);
    expect(local.replaceCount, 0);
    expect(keys.values, isEmpty);
  });

  test(
    'sync publish snapshot local bằng optimistic revision kế tiếp',
    () async {
      await seedRemote([first]);
      local.accounts.add(second);

      final completed = _right(await useCase.sync());

      expect(completed, isA<EncryptedSyncCompleted>());
      expect(remote.snapshot?.envelope.revision, 2);
      expect(metadata.revisions[userId], 2);
      final decrypted = await cipher.decryptAccounts(
        envelope: remote.snapshot!.envelope,
        dataKeyBytes: keys.values[userId]!,
        userId: userId,
      );
      expect(decrypted, [first, second]);
    },
  );

  test(
    'remote revision mới tạo conflict và dùng cloud thay local atomically',
    () async {
      final recoveryCode = await seedRemote([first]);
      final remoteKey = keys.values[userId]!;
      final wrapped = remote.snapshot!.wrappedDataKey;
      final cloudEnvelope = await cipher.encryptAccounts(
        accounts: const [second],
        dataKeyBytes: remoteKey,
        userId: userId,
        revision: 2,
      );
      await remote.publish(
        userId: userId,
        expectedRevision: 1,
        envelope: cloudEnvelope,
        wrappedDataKey: wrapped,
      );
      expect(recoveryCode, startsWith('HA1-'));

      final conflict = _right(await useCase.sync());
      expect(conflict, isA<EncryptedSyncConflict>());
      expect(local.accounts, [first]);

      final resolved = _right(await useCase.useCloud());
      expect(resolved, isA<EncryptedSyncCompleted>());
      expect(local.accounts, [second]);
      expect(local.replaceCount, 1);
      expect(metadata.revisions[userId], 2);
    },
  );

  test(
    'giữ local tạo revision mới, không delete snapshot trước publish',
    () async {
      await seedRemote([first]);
      final dataKey = keys.values[userId]!;
      final wrapped = remote.snapshot!.wrappedDataKey;
      final cloudEnvelope = await cipher.encryptAccounts(
        accounts: const [second],
        dataKeyBytes: dataKey,
        userId: userId,
        revision: 2,
      );
      await remote.publish(
        userId: userId,
        expectedRevision: 1,
        envelope: cloudEnvelope,
        wrappedDataKey: wrapped,
      );
      _right(await useCase.sync());

      final resolved = _right(await useCase.keepLocal());

      expect(resolved, isA<EncryptedSyncCompleted>());
      expect(remote.snapshot?.envelope.revision, 3);
      final decrypted = await cipher.decryptAccounts(
        envelope: remote.snapshot!.envelope,
        dataKeyBytes: dataKey,
        userId: userId,
      );
      expect(decrypted, [first]);
    },
  );

  test(
    'publish conflict giữ nguyên cloud snapshot và revision metadata',
    () async {
      await seedRemote([first]);
      local.accounts.add(second);
      remote.failNextPublishWithConflict = true;

      final result = await useCase.sync();

      expect(
        result.fold((failure) => failure, (_) => null),
        isA<SyncRevisionConflictFailure>(),
      );
      expect(remote.snapshot?.envelope.revision, 1);
      expect(metadata.revisions[userId], 1);
    },
  );

  test(
    'read-after-write lệch encrypted payload không xác nhận revision mới',
    () async {
      await seedRemote([first]);
      local.accounts.add(second);
      remote.tamperNextDownloadAfterPublish = true;

      final result = await useCase.sync();

      expect(
        result.fold((failure) => failure, (_) => null),
        isA<SyncOperationFailure>(),
      );
      expect(remote.snapshot?.envelope.revision, 2);
      expect(metadata.revisions[userId], 1);
    },
  );
}

EncryptedVaultSyncUseCase _createUseCase({
  required String userId,
  required VaultCipher cipher,
  required _MemoryEncryptedVaultRepository remote,
  required _MemoryAuthenticatorRepository local,
  required _MemoryVaultKeyRepository keys,
  required _MemoryMetadataRepository metadata,
}) => EncryptedVaultSyncUseCase(
  _MemoryAuthRepository(UserEntity(id: userId)),
  local,
  remote,
  keys,
  metadata,
  cipher,
);

T _right<T>(Either<Failure, T> result) => result.fold(
  (failure) => throw TestFailure(failure.message),
  (value) => value,
);

class _MemoryEncryptedVaultRepository implements EncryptedVaultRepository {
  EncryptedVaultSnapshot? snapshot;
  bool failNextPublishWithConflict = false;
  bool failNextPublishAfterCommit = false;
  bool tamperNextDownloadAfterPublish = false;
  bool _tamperNextDownload = false;

  @override
  Future<Either<Failure, EncryptedVaultSnapshot?>> download({
    required String userId,
  }) async {
    final current = snapshot;
    if (!_tamperNextDownload || current == null) return Right(current);
    _tamperNextDownload = false;
    return Right(
      EncryptedVaultSnapshot(
        envelope: EncryptedVaultEnvelope(
          formatVersion: current.envelope.formatVersion,
          revision: current.envelope.revision,
          cipher: current.envelope.cipher,
          nonce: current.envelope.nonce,
          ciphertext: '${current.envelope.ciphertext}TEST_ONLY_TAMPER',
          authTag: current.envelope.authTag,
        ),
        wrappedDataKey: current.wrappedDataKey,
        updatedAt: current.updatedAt,
      ),
    );
  }

  @override
  Future<Either<Failure, int>> publish({
    required String userId,
    required int expectedRevision,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  }) async {
    if (failNextPublishWithConflict) {
      failNextPublishWithConflict = false;
      return const Left(
        SyncRevisionConflictFailure('TEST_ONLY revision conflict'),
      );
    }
    final currentRevision = snapshot?.envelope.revision ?? 0;
    if (currentRevision != expectedRevision ||
        envelope.revision != expectedRevision + 1) {
      return const Left(
        SyncRevisionConflictFailure('TEST_ONLY revision conflict'),
      );
    }
    snapshot = EncryptedVaultSnapshot(
      envelope: envelope,
      wrappedDataKey: wrappedDataKey,
      updatedAt: DateTime.utc(2026, 7, 18, 12, envelope.revision),
    );
    if (failNextPublishAfterCommit) {
      failNextPublishAfterCommit = false;
      return const Left(
        SyncOperationFailure('TEST_ONLY transport failed after commit'),
      );
    }
    if (tamperNextDownloadAfterPublish) {
      tamperNextDownloadAfterPublish = false;
      _tamperNextDownload = true;
    }
    return Right(envelope.revision);
  }
}

class _MemoryVaultKeyRepository implements VaultKeyRepository {
  final Map<String, List<int>> values = {};
  bool failNextWrite = false;

  @override
  Future<Either<Failure, List<int>?>> read(String userId) async =>
      Right(values[userId]);

  @override
  Future<Either<Failure, Unit>> write(
    String userId,
    List<int> dataKeyBytes,
  ) async {
    if (failNextWrite) {
      failNextWrite = false;
      return const Left(StorageFailure('TEST_ONLY key write failure'));
    }
    values[userId] = List.unmodifiable(dataKeyBytes);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(String userId) async {
    values.remove(userId);
    return const Right(unit);
  }
}

class _MemoryMetadataRepository implements EncryptedSyncMetadataRepository {
  final Map<String, int> revisions = {};
  final Map<String, bool> enabled = {};

  void clear() {
    revisions.clear();
    enabled.clear();
  }

  @override
  int? readLastRevision(String userId) => revisions[userId];

  @override
  Future<void> writeLastRevision(String userId, int revision) async {
    revisions[userId] = revision;
  }

  @override
  bool readEnabled(String userId) => enabled[userId] ?? false;

  @override
  Future<void> writeEnabled(String userId, bool value) async {
    enabled[userId] = value;
  }
}

class _MemoryAuthenticatorRepository implements AuthenticatorRepository {
  final List<AuthenticatorAccount> accounts;
  int replaceCount = 0;

  _MemoryAuthenticatorRepository(List<AuthenticatorAccount> initial)
    : accounts = [...initial];

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List.unmodifiable(accounts));

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> replacement,
  ) async {
    accounts
      ..clear()
      ..addAll(replacement);
    replaceCount++;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async => throw UnimplementedError();
}

class _MemoryAuthRepository implements AuthRepository {
  final UserEntity user;

  _MemoryAuthRepository(this.user);

  @override
  UserEntity? get currentUserEntity => user;

  @override
  Stream<UserEntity?> get authEntityChanges => Stream.value(user);

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(user);

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name,
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> signOut() async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      throw UnimplementedError();
}
