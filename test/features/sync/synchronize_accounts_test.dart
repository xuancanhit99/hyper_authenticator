import 'package:flutter_test/flutter_test.dart';
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
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_metadata_repository.dart';
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
    synchronize = SynchronizeAccounts(auth, local, cloud, metadata);
  });

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

class _MemoryMetadataRepository implements AccountSyncMetadataRepository {
  AccountSyncMetadata value = const AccountSyncMetadata({});

  @override
  Future<AccountSyncMetadata> read() async => value;

  @override
  Future<void> write(AccountSyncMetadata metadata) async {
    value = AccountSyncMetadata(Map.unmodifiable(metadata.records));
  }
}

class _FakeCloudRepository implements CloudAccountRepository {
  final Map<String, Map<String, CloudAccountRecord>> _records = {};
  int listCalls = 0;
  bool failList = false;
  var _clock = DateTime.utc(2026, 8, 4);

  @override
  Future<List<CloudAccountRecord>> list({required String userId}) async {
    listCalls++;
    if (failList) throw const ServerException('offline');
    return List.unmodifiable(_records[userId]?.values ?? const []);
  }

  @override
  Future<CloudAccountRecord> upsert({
    required String userId,
    required AuthenticatorAccount account,
    required int expectedRevision,
  }) async {
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
          .where((record) => !record.isDeleted)
          .map((record) => record.account!);

  DateTime _tick() {
    _clock = _clock.add(const Duration(seconds: 1));
    return _clock;
  }
}
