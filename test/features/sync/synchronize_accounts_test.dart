import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:hyper_authenticator/features/authenticator/data/datasources/authenticator_local_data_source.dart';
import '../../support/memory_local_vault.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/cloud_account_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/synchronize_accounts.dart';

void main() {
  const userA = UserEntity(id: 'user-a', email: 'a@example.test');
  const userB = UserEntity(id: 'user-b', email: 'b@example.test');
  const first = AuthenticatorAccount(
    id: '11111111-1111-4111-8111-111111111111',
    issuer: 'Alpha',
    accountName: 'alpha@example.test',
    secretKey: 'JBSWY3DPEHPK3PXP',
  );
  const second = AuthenticatorAccount(
    id: '22222222-2222-4222-8222-222222222222',
    issuer: 'Beta',
    accountName: 'beta@example.test',
    secretKey: 'KRUGS4ZANFZSAYJA',
    algorithm: 'SHA256',
    digits: 8,
    period: 60,
  );

  late _FakeAuthRepository auth;
  late _FakeAuthenticatorRepository local;
  late _FakeCloudRepository cloud;
  late _MemoryMetadataRepository metadata;
  late SynchronizeAccounts synchronize;

  setUp(() {
    auth = _FakeAuthRepository(userA);
    local = _FakeAuthenticatorRepository();
    cloud = _FakeCloudRepository();
    metadata = _MemoryMetadataRepository();
    synchronize = SynchronizeAccounts(
      auth,
      MemoryLocalVault(
        local.accounts,
        () => metadata.value,
        (value) => metadata.value = value,
      ),
      cloud,
    );
  });

  AuthenticatorLocalDataSourceImpl vault(_FaultStore store) =>
      AuthenticatorLocalDataSourceImpl(
        secureStorage: store,
        uuid: const Uuid(),
      );

  test(
    'failed upload never publishes downloaded payload without its owner',
    () async {
      final store = _FaultStore();
      final source = vault(store);
      await source.saveAccount(first);
      cloud.seed(userA.id, second);
      cloud.failUpsert = true;
      expect(
        (await SynchronizeAccounts(auth, source, cloud)()).isLeft(),
        isTrue,
      );
      final reopened = vault(store);
      final snapshot = await reopened.readVault();
      expect(snapshot.accounts, [first]);
      expect(snapshot.metadata.records[first.id]?.ownerUserId, userA.id);
      auth.current = userB;
      cloud.failUpsert = false;
      _right(await SynchronizeAccounts(auth, reopened, cloud)());
      expect(cloud.liveAccounts(userB.id), isEmpty);
    },
  );

  test('delete before first upload persists a remote tombstone', () async {
    final store = _FaultStore();
    final source = vault(store);
    await source.saveAccount(first);
    cloud.failList = true;
    expect((await SynchronizeAccounts(auth, source, cloud)()).isLeft(), isTrue);
    await source.deleteAccount(first.id);
    cloud.failList = false;
    final result =
        _right(await SynchronizeAccounts(auth, vault(store), cloud)())
            as AccountSyncCompleted;
    expect(result.deletedCount, 1);
    expect(cloud.record(userA.id, first.id)?.isDeleted, isTrue);
    expect((await vault(store).readVault()).deletedAccountIds, isEmpty);
    expect(
      () => cloud.upsert(userId: userA.id, account: first, expectedRevision: 0),
      throwsA(isA<CloudAccountTombstonedException>()),
    );
  });

  for (final boundary in ['record:', 'manifest:', 'commit:', 'after-commit']) {
    test(
      'download crash at $boundary reopens with payload and owner together',
      () async {
        final store = _FaultStore();
        final source = vault(store);
        await source.readVault();
        cloud.seed(userA.id, second);
        store.failure = boundary;
        expect(
          (await SynchronizeAccounts(auth, source, cloud)()).isLeft(),
          isTrue,
        );
        store.failure = null;
        final reopened = vault(store);
        final snapshot = await reopened.readVault();
        if (snapshot.accounts.any((a) => a.id == second.id)) {
          expect(snapshot.metadata.records[second.id]?.ownerUserId, userA.id);
        }
        auth.current = userB;
        _right(await SynchronizeAccounts(auth, reopened, cloud)());
        expect(cloud.liveAccounts(userB.id), isEmpty);
      },
    );
  }

  for (final during in ['list', 'upsert']) {
    for (final mutation in ['edit', 'delete', 'add']) {
      test('$mutation during $during survives CAS retry and restart', () async {
        final store = _FaultStore();
        final source = vault(store);
        await source.saveAccount(first);
        final sync = SynchronizeAccounts(auth, source, cloud);
        _right(await sync());
        final edit = AuthenticatorAccount(
          id: first.id,
          issuer: 'TEST_ONLY_USER_EDIT',
          accountName: first.accountName,
          secretKey: first.secretKey,
        );
        if (during == 'upsert') {
          await source.updateAccount(
            AuthenticatorAccount(
              id: first.id,
              issuer: 'TEST_ONLY_PENDING',
              accountName: first.accountName,
              secretKey: first.secretKey,
            ),
          );
        } else {
          cloud.forceUpdate(
            userA.id,
            AuthenticatorAccount(
              id: first.id,
              issuer: 'TEST_ONLY_REMOTE',
              accountName: first.accountName,
              secretKey: first.secretKey,
            ),
          );
        }
        Future<void> change() async {
          if (mutation == 'edit') await source.updateAccount(edit);
          if (mutation == 'delete') await source.deleteAccount(first.id);
          if (mutation == 'add') await source.saveAccount(second);
        }

        if (during == 'list') {
          cloud.onList = change;
        } else {
          cloud.onUpsert = change;
        }
        _right(await sync());
        final reopened = await vault(store).readVault();
        if (mutation == 'delete') {
          expect(reopened.accounts, isEmpty);
          expect(cloud.record(userA.id, first.id)?.isDeleted, isTrue);
        } else if (mutation == 'edit') {
          expect(reopened.accounts, [edit]);
          expect(cloud.record(userA.id, first.id)?.account, edit);
        } else {
          expect(
            reopened.accounts.map((a) => a.id),
            containsAll([first.id, second.id]),
          );
          expect(
            cloud.liveAccounts(userA.id).map((a) => a.id),
            containsAll([first.id, second.id]),
          );
        }
      });
    }
  }

  test(
    'session switch while downloading cannot publish or upload across users',
    () async {
      final store = _FaultStore();
      final source = vault(store);
      await source.saveAccount(first);
      cloud.seed(userA.id, second);
      cloud.onList = () async {
        auth.current = userB;
      };
      expect(
        (await SynchronizeAccounts(auth, source, cloud)()).isLeft(),
        isTrue,
      );
      final snapshot = await vault(store).readVault();
      expect(snapshot.accounts, [first]);
      expect(snapshot.metadata.records[first.id]?.ownerUserId, userA.id);
      _right(await SynchronizeAccounts(auth, vault(store), cloud)());
      expect(cloud.liveAccounts(userB.id), isEmpty);
    },
  );

  test('signed out giữ local-only và không gọi cloud', () async {
    auth.current = null;
    local.accounts.add(first);

    final result = _right(await synchronize());

    expect(result, isA<AccountSyncSignedOut>());
    expect(local.accounts, [first]);
    expect(cloud.listCalls, 0);
  });

  test('first sign-in merge cloud xuống local và upload mã local', () async {
    local.accounts.add(first);
    cloud.seed(userA.id, second);

    final result = _right(await synchronize()) as AccountSyncCompleted;

    expect(local.accounts.toSet(), {first, second});
    expect(cloud.liveAccounts(userA.id).toSet(), {first, second});
    expect(result.uploadedCount, 1);
    expect(result.downloadedCount, 1);
    expect(metadata.value.records[first.id]?.ownerUserId, userA.id);
    expect(metadata.value.records[second.id]?.ownerUserId, userA.id);
  });

  test('xóa local sau sync tạo tombstone cloud', () async {
    local.accounts.add(first);
    _right(await synchronize());
    local.accounts.clear();

    final result = _right(await synchronize()) as AccountSyncCompleted;

    expect(cloud.record(userA.id, first.id)?.isDeleted, isTrue);
    expect(result.deletedCount, 1);
    expect(metadata.value.records[first.id]?.isDeleted, isTrue);
  });

  test('tombstone cloud xóa local và thắng update offline', () async {
    local.accounts.add(first);
    _right(await synchronize());
    local.accounts[0] = const AuthenticatorAccount(
      id: '11111111-1111-4111-8111-111111111111',
      issuer: 'Alpha edited offline',
      accountName: 'alpha@example.test',
      secretKey: 'JBSWY3DPEHPK3PXP',
    );
    cloud.tombstone(userA.id, first.id);

    final result = _right(await synchronize()) as AccountSyncCompleted;

    expect(local.accounts, isEmpty);
    expect(result.deletedCount, 1);
    expect(cloud.record(userA.id, first.id)?.isDeleted, isTrue);
  });

  test('remote update thay local sạch nhưng local dirty được upload', () async {
    local.accounts.add(first);
    _right(await synchronize());

    final remoteEdit = AuthenticatorAccount(
      id: first.id,
      issuer: 'Remote edit',
      accountName: first.accountName,
      secretKey: first.secretKey,
    );
    cloud.forceUpdate(userA.id, remoteEdit);
    _right(await synchronize());
    expect(local.accounts.single.issuer, 'Remote edit');

    local.accounts[0] = AuthenticatorAccount(
      id: first.id,
      issuer: 'Local edit',
      accountName: first.accountName,
      secretKey: first.secretKey,
    );
    _right(await synchronize());
    expect(cloud.liveAccounts(userA.id).single.issuer, 'Local edit');
  });

  test('account đã thuộc user A không tự upload sang user B', () async {
    local.accounts.add(first);
    _right(await synchronize());
    auth.current = userB;

    _right(await synchronize());

    expect(cloud.liveAccounts(userB.id), isEmpty);
    expect(local.accounts, [first]);
    expect(metadata.value.records[first.id]?.ownerUserId, userA.id);
  });

  test(
    'cloud lỗi vẫn bind ownership trước network và không mutate local',
    () async {
      local.accounts.add(first);
      cloud.failList = true;

      final result = await synchronize();

      expect(result.isLeft(), isTrue);
      expect(local.accounts, [first]);
      expect(metadata.value.records[first.id]?.ownerUserId, userA.id);

      auth.current = userB;
      cloud.failList = false;
      _right(await synchronize());
      expect(cloud.liveAccounts(userB.id), isEmpty);
    },
  );

  test(
    'legacy invalid first account does not starve upload or delete on retry',
    () async {
      local.accounts.add(second);
      _right(await synchronize());
      local.accounts.clear(); // pending deletion of a previously synced account
      final invalid = AuthenticatorAccount(
        id: '33333333-3333-4333-8333-333333333333',
        issuer: 'X' * 257,
        accountName: 'test@example.invalid',
        secretKey: 'JBSWY3DPEHPK3PXP',
      );
      local.accounts.addAll([invalid, first]);

      for (var attempt = 0; attempt < 2; attempt++) {
        final result = await synchronize();
        expect(result.isRight(), isTrue);
        final completed = _right(result) as AccountSyncCompleted;
        expect(completed.blockedAccountCount, 1);
        expect(completed.uploadedCount, attempt == 0 ? 1 : 0);
        expect(completed.deletedCount, attempt == 0 ? 1 : 0);
        expect(cloud.liveAccounts(userA.id), [first]);
        expect(cloud.record(userA.id, second.id)?.isDeleted, isTrue);
        expect(local.accounts, [invalid, first]);
        expect(metadata.value.records[invalid.id]?.ownerUserId, userA.id);
        expect(metadata.value.records[invalid.id]?.syncedFingerprint, isNull);
      }
      expect(cloud.upsertAttempts, isNot(contains(invalid.id)));
      expect(metadata.value.records[first.id]?.remoteRevision, 1);

      // A user can fix the label; no data was truncated/dropped while blocked.
      local.accounts[0] = AuthenticatorAccount(
        id: invalid.id,
        issuer: 'Fixed',
        accountName: invalid.accountName,
        secretKey: invalid.secretKey,
      );
      final fixed = _right(await synchronize()) as AccountSyncCompleted;
      expect(fixed.blockedAccountCount, 0);
      expect(cloud.liveAccounts(userA.id).length, 2);
      auth.current = userB;
      final foreign = _right(await synchronize()) as AccountSyncCompleted;
      expect(foreign.blockedAccountCount, 0);
      expect(cloud.liveAccounts(userB.id), isEmpty);
    },
  );

  test(
    'transient upload failure remains failure with pending metadata',
    () async {
      local.accounts.add(first);
      cloud.failUpsert = true;
      expect((await synchronize()).isLeft(), isTrue);
      expect(local.accounts, [first]);
      expect(metadata.value.records[first.id]?.ownerUserId, userA.id);
      expect(metadata.value.records[first.id]?.syncedFingerprint, isNull);
      cloud.failUpsert = false;
      final retried = _right(await synchronize()) as AccountSyncCompleted;
      expect(retried.uploadedCount, 1);
      expect(retried.blockedAccountCount, 0);
    },
  );
  test(
    'blocked remote preserves data while valid records continue and can be repaired',
    () async {
      const blockedId = '33333333-3333-4333-8333-333333333333';
      cloud.block(userA.id, blockedId);
      cloud.seed(userA.id, second);
      local.accounts.add(first);
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = _right(await synchronize()) as AccountSyncCompleted;
        expect(result.blockedAccountCount, 1);
        expect(local.accounts.toSet(), {first, second});
        expect(metadata.value.records.containsKey(blockedId), isFalse);
        expect(cloud.record(userA.id, blockedId)?.isBlocked, isTrue);
        expect(cloud.record(userA.id, first.id)?.account, first);
      }
      final repaired = AuthenticatorAccount(
        id: blockedId,
        issuer: 'Repaired',
        accountName: 'test@example.invalid',
        secretKey: 'JBSWY3DPEHPK3PXP',
      );
      local.accounts.add(repaired);
      final result = _right(await synchronize()) as AccountSyncCompleted;
      expect(result.blockedAccountCount, 0);
      expect(cloud.record(userA.id, blockedId)?.account, repaired);
      expect(cloud.record(userA.id, blockedId)?.revision, 2);
    },
  );

  test(
    'explicit local delete still tombstones a blocked cloud record',
    () async {
      local.accounts.add(first);
      _right(await synchronize());
      cloud.block(userA.id, first.id);
      local.accounts.clear();
      final result = _right(await synchronize()) as AccountSyncCompleted;
      expect(result.blockedAccountCount, 0);
      expect(result.deletedCount, 1);
      expect(cloud.record(userA.id, first.id)?.isDeleted, isTrue);
      expect(metadata.value.records[first.id]?.isDeleted, isTrue);
    },
  );
  test(
    'same blocked ID is counted once and stays isolated across users',
    () async {
      final invalid = AuthenticatorAccount(
        id: first.id,
        issuer: first.issuer,
        accountName: first.accountName,
        secretKey: 'A' * 17,
      );
      local.accounts.addAll([invalid, second]);
      cloud.block(userA.id, first.id);
      final result = _right(await synchronize()) as AccountSyncCompleted;
      expect(result.blockedAccountCount, 1);
      expect(local.accounts, [invalid, second]);
      expect(cloud.record(userA.id, second.id)?.account, second);
      auth.current = userB;
      cloud.block(userB.id, first.id);
      final foreign = _right(await synchronize()) as AccountSyncCompleted;
      expect(foreign.blockedAccountCount, 0);
      expect(cloud.upsertAttempts, [second.id]);
    },
  );

  for (final conflict in [false, true]) {
    test(
      'inflight tombstone resolves blocked count (conflict=$conflict)',
      () async {
        local.accounts.add(first);
        _right(await synchronize());
        cloud.block(userA.id, first.id);
        local.accounts[0] = AuthenticatorAccount(
          id: first.id,
          issuer: 'Renamed',
          accountName: first.accountName,
          secretKey: first.secretKey,
        );
        cloud.tombstoneOnUpsert = true;
        cloud.tombstoneViaConflict = conflict;
        final result = _right(await synchronize()) as AccountSyncCompleted;
        expect(result.blockedAccountCount, 0);
        expect(result.deletedCount, 1);
        expect(local.accounts, isEmpty);
        expect(metadata.value.records[first.id]?.isDeleted, isTrue);
      },
    );
  }
}

T _right<T>(Either<Failure, T> result) => result.fold(
  (failure) => throw TestFailure(failure.message),
  (value) => value,
);

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.current);

  UserEntity? current;

  @override
  UserEntity? get currentUserEntity => current;

  @override
  Stream<UserEntity?> get authEntityChanges => const Stream.empty();

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(current);

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      const Right(null);

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async => Right(current!);

  @override
  Future<Either<Failure, void>> signInWithGoogle() async => const Right(null);

  @override
  Future<Either<Failure, void>> signOut() async => const Right(null);

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String email,
    required String password,
  }) async => Right(current!);

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      const Right(null);
}

class _FakeAuthenticatorRepository implements AuthenticatorRepository {
  final List<AuthenticatorAccount> accounts = [];

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) async {
    final before = accounts.length;
    accounts.removeWhere((account) => account.id == id);
    return before == accounts.length
        ? const Left(AccountNotFoundFailure('missing'))
        : const Right(unit);
  }

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List.unmodifiable(accounts));

  @override
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> replacement,
  ) async {
    accounts
      ..clear()
      ..addAll(replacement);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) async {
    final index = accounts.indexWhere((value) => value.id == account.id);
    if (index == -1) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }
    return Right(account);
  }

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async => const Right(unit);
}

class _MemoryMetadataRepository {
  AccountSyncMetadata value = const AccountSyncMetadata({});
}

class _FakeCloudRepository implements CloudAccountRepository {
  Future<void> Function()? onList;
  Future<void> Function()? onUpsert;
  final Map<String, Map<String, CloudAccountRecord>> _records = {};
  int listCalls = 0;
  bool failList = false;
  bool failUpsert = false;
  bool tombstoneOnUpsert = false;
  bool tombstoneViaConflict = false;
  final List<String> upsertAttempts = [];
  var _clock = DateTime.utc(2026, 8, 4);

  @override
  Future<List<CloudAccountRecord>> list({required String userId}) async {
    listCalls++;
    final callback = onList;
    onList = null;
    if (callback != null) await callback();
    if (failList) throw const ServerException('offline');
    return List.unmodifiable(_records[userId]?.values ?? const []);
  }

  @override
  Future<CloudAccountRecord> upsert({
    required String userId,
    required AuthenticatorAccount account,
    required int expectedRevision,
  }) async {
    upsertAttempts.add(account.id);
    final callback = onUpsert;
    onUpsert = null;
    if (callback != null) await callback();
    if (failUpsert) throw const ServerException('TEST_ONLY offline upload');
    if (tombstoneOnUpsert) {
      tombstone(userId, account.id);
      if (tombstoneViaConflict) {
        throw const CloudAccountRevisionConflictException();
      }
      throw const CloudAccountTombstonedException();
    }
    if (account.issuer.runes.length > 256 ||
        account.accountName.runes.length > 512 ||
        account.secretKey.length < 16 ||
        account.secretKey.length > 1024) {
      throw const ServerException('TEST_ONLY payload rejected by SQL bounds');
    }
    final current = record(userId, account.id);
    if (current?.isDeleted == true) {
      throw const CloudAccountTombstonedException();
    }
    if ((current?.revision ?? 0) != expectedRevision) {
      throw const CloudAccountRevisionConflictException();
    }
    final result = CloudAccountRecord(
      accountId: account.id,
      revision: expectedRevision + 1,
      updatedAt: _tick(),
      deletedAt: null,
      account: account,
    );
    (_records[userId] ??= {})[account.id] = result;
    return result;
  }

  @override
  Future<CloudAccountRecord> delete({
    required String userId,
    required String accountId,
    required int expectedRevision,
  }) async {
    final current = record(userId, accountId);
    if (current?.isDeleted == true) return current!;
    if ((current?.revision ?? 0) != expectedRevision) {
      throw const CloudAccountRevisionConflictException();
    }
    final deletedAt = _tick();
    final result = CloudAccountRecord(
      accountId: accountId,
      revision: expectedRevision + 1,
      updatedAt: deletedAt,
      deletedAt: deletedAt,
      account: null,
    );
    (_records[userId] ??= {})[accountId] = result;
    return result;
  }

  void block(String userId, String accountId) {
    final revision = (record(userId, accountId)?.revision ?? 0) + 1;
    (_records[userId] ??= {})[accountId] = CloudAccountRecord(
      accountId: accountId,
      revision: revision,
      updatedAt: _tick(),
      deletedAt: null,
      account: null,
      isBlocked: true,
    );
  }

  void seed(String userId, AuthenticatorAccount account) {
    (_records[userId] ??= {})[account.id] = CloudAccountRecord(
      accountId: account.id,
      revision: 1,
      updatedAt: _tick(),
      deletedAt: null,
      account: account,
    );
  }

  void forceUpdate(String userId, AuthenticatorAccount account) {
    final current = record(userId, account.id)!;
    (_records[userId] ??= {})[account.id] = CloudAccountRecord(
      accountId: account.id,
      revision: current.revision + 1,
      updatedAt: _tick(),
      deletedAt: null,
      account: account,
    );
  }

  void tombstone(String userId, String accountId) {
    final current = record(userId, accountId)!;
    final deletedAt = _tick();
    (_records[userId] ??= {})[accountId] = CloudAccountRecord(
      accountId: accountId,
      revision: current.revision + 1,
      updatedAt: deletedAt,
      deletedAt: deletedAt,
      account: null,
    );
  }

  CloudAccountRecord? record(String userId, String accountId) =>
      _records[userId]?[accountId];

  Iterable<AuthenticatorAccount> liveAccounts(String userId) =>
      (_records[userId]?.values ?? const <CloudAccountRecord>[])
          .where((record) => !record.isDeleted && !record.isBlocked)
          .map((record) => record.account!);

  DateTime _tick() {
    _clock = _clock.add(const Duration(seconds: 1));
    return _clock;
  }
}

class _FaultStore implements SecureKeyValueStore {
  final values = <String, String>{};
  String? failure;
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (failure != null &&
        failure != 'after-commit' &&
        key.startsWith('ha:v2:$failure')) {
      throw StateError('TEST_ONLY interrupted write');
    }
    values[key] = value;
    if (failure == 'after-commit' && key.startsWith('ha:v2:commit:')) {
      throw StateError('TEST_ONLY process interrupted after durable commit');
    }
  }
}
