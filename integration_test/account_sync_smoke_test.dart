import 'dart:math';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_metadata_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/cloud_account_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/synchronize_accounts.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _allowRemoteMutation = bool.fromEnvironment(
  'ALLOW_ACCOUNT_SYNC_REMOTE_TEST_MUTATION',
);
const _testEmail = String.fromEnvironment('ACCOUNT_SYNC_TEST_EMAIL');
const _testPassword = String.fromEnvironment('ACCOUNT_SYNC_TEST_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account sync upload, new-device download và tombstone', (
    tester,
  ) async {
    expect(
      _allowRemoteMutation,
      isTrue,
      reason: 'Chỉ harness isolated user/emulator được chạy remote mutation.',
    );
    expect(_testEmail, isNotEmpty);
    expect(_testPassword, isNotEmpty);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('biometric_enabled', false);
    await app.main();
    await tester.pump(const Duration(milliseconds: 500));

    final auth = di.sl<AuthRepository>();
    final local = di.sl<AuthenticatorRepository>();
    final remote = di.sl<CloudAccountRepository>();
    final sync = di.sl<AccountSynchronizer>();
    final user = _right(
      await auth.signInWithPassword(email: _testEmail, password: _testPassword),
    );
    await _waitUntil(
      () async => di.sl<AuthBloc>().state is AuthAuthenticated,
      reason: 'AuthBloc không nhận session của isolated user.',
    );

    final account = AuthenticatorAccount(
      id: const Uuid().v4(),
      issuer: 'TEST ONLY account sync',
      accountName: 'not-a-real-account@example.test',
      secretKey: _ephemeralBase32Secret(),
      algorithm: 'SHA256',
      digits: 8,
      period: 45,
    );

    try {
      _right(await local.replaceAccounts(const []));
      _right(await local.saveAccount(account));
      final uploaded = _right(await sync()) as AccountSyncCompleted;
      expect(uploaded.uploadedCount, 1);
      final remoteRows = await remote.list(userId: user.id);
      expect(remoteRows.where((row) => !row.isDeleted), hasLength(1));

      final freshLocal = _MemoryAccountRepository();
      final freshSync = SynchronizeAccounts(
        _CurrentUserAuthRepository(user),
        freshLocal,
        remote,
        _MemoryMetadataRepository(),
      );
      final downloaded = _right(await freshSync()) as AccountSyncCompleted;
      expect(downloaded.downloadedCount, 1);
      expect(freshLocal.accounts, [account]);

      final realtimeAccount = AuthenticatorAccount(
        id: const Uuid().v4(),
        issuer: 'TEST ONLY realtime wake-up',
        accountName: 'realtime@example.test',
        secretKey: _ephemeralBase32Secret(),
      );
      final realtimeCreated = await remote.upsert(
        userId: user.id,
        account: realtimeAccount,
        expectedRevision: 0,
      );
      await _waitUntil(() async {
        final accounts = _right(await local.getAccounts());
        return accounts.any((candidate) => candidate.id == realtimeAccount.id);
      }, reason: 'Private Realtime signal không kích hoạt download local.');

      await remote.delete(
        userId: user.id,
        accountId: realtimeAccount.id,
        expectedRevision: realtimeCreated.revision,
      );
      await _waitUntil(() async {
        final accounts = _right(await local.getAccounts());
        return accounts.every(
          (candidate) => candidate.id != realtimeAccount.id,
        );
      }, reason: 'Private Realtime tombstone không xóa local.');

      _right(await local.deleteAccount(account.id));
      final deleted = _right(await sync()) as AccountSyncCompleted;
      expect(deleted.deletedCount, 1);
      final tombstone = (await remote.list(
        userId: user.id,
      )).singleWhere((row) => row.accountId == account.id);
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.account, isNull);
    } finally {
      _right(await local.replaceAccounts(const []));
      await auth.signOut();
    }
  });
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  required String reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) throw TestFailure(reason);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String _ephemeralBase32Secret() {
  final random = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(20, (_) => random.nextInt(256)),
  );
  return base32.encode(bytes).replaceAll('=', '');
}

T _right<T>(Either<Failure, T> result) => result.fold(
  (failure) => throw TestFailure(failure.message),
  (value) => value,
);

class _MemoryMetadataRepository implements AccountSyncMetadataRepository {
  AccountSyncMetadata value = const AccountSyncMetadata({});

  @override
  Future<AccountSyncMetadata> read() async => value;

  @override
  Future<void> write(AccountSyncMetadata metadata) async {
    value = AccountSyncMetadata(Map.unmodifiable(metadata.records));
  }
}

class _CurrentUserAuthRepository implements AuthRepository {
  const _CurrentUserAuthRepository(this.user);

  final UserEntity user;

  @override
  UserEntity get currentUserEntity => user;

  @override
  Stream<UserEntity?> get authEntityChanges => Stream.value(user);

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(user);

  @override
  Future<Either<Failure, void>> recoverPassword(String email) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> signOut() => throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) =>
      throw UnimplementedError();
}

class _MemoryAccountRepository implements AuthenticatorRepository {
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
    final found = accounts.any((account) => account.id == id);
    accounts.removeWhere((account) => account.id == id);
    return found
        ? const Right(unit)
        : const Left(AccountNotFoundFailure('missing'));
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
