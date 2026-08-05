import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_signal.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_signal_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/synchronize_accounts.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';

void main() {
  test('session restore và local mutation đều tự kích hoạt sync', () async {
    final authRepository = _AuthRepository();
    final accountRepository = _AccountRepository();
    final authBloc = AuthBloc(authRepository);
    final accountsBloc = AccountsBloc(
      getAccounts: GetAccounts(accountRepository),
      addAccount: AddAccount(accountRepository),
      deleteAccount: DeleteAccount(accountRepository),
      updateAccount: UpdateAccount(accountRepository),
      importAccounts: ImportAccounts(accountRepository),
    );
    final synchronizer = _Synchronizer();
    final signals = _SignalRepository();
    final syncBloc = SyncBloc(synchronizer, signals, authBloc, accountsBloc);
    addTearDown(syncBloc.close);
    addTearDown(accountsBloc.close);
    addTearDown(authBloc.close);

    authBloc.add(AuthCheckRequested());
    await _waitUntil(() => synchronizer.calls == 1);
    expect(syncBloc.state, isA<SyncReady>());

    accountsBloc.add(
      const AddAccountRequested(
        issuer: 'Example',
        accountName: 'user@example.test',
        secretKey: 'JBSWY3DPEHPK3PXP',
        algorithm: 'SHA1',
        digits: 6,
        period: 30,
      ),
    );
    await _waitUntil(() => synchronizer.calls == 2);
    expect(accountRepository.accounts, hasLength(1));
  });

  test('logout dừng sync và chuyển trạng thái local-only', () async {
    final authRepository = _AuthRepository();
    final accountRepository = _AccountRepository();
    final authBloc = AuthBloc(authRepository);
    final accountsBloc = AccountsBloc(
      getAccounts: GetAccounts(accountRepository),
      addAccount: AddAccount(accountRepository),
      deleteAccount: DeleteAccount(accountRepository),
      updateAccount: UpdateAccount(accountRepository),
      importAccounts: ImportAccounts(accountRepository),
    );
    final synchronizer = _Synchronizer();
    final signals = _SignalRepository();
    final syncBloc = SyncBloc(synchronizer, signals, authBloc, accountsBloc);
    addTearDown(syncBloc.close);
    addTearDown(accountsBloc.close);
    addTearDown(authBloc.close);

    authBloc.add(AuthCheckRequested());
    await _waitUntil(() => synchronizer.calls == 1);
    authRepository.current = null;
    authBloc.add(AuthSignOutRequested());
    await _waitUntil(() => syncBloc.state is SyncSignedOut);

    expect(synchronizer.calls, 1);
    expect(accountRepository.accounts, isEmpty);
    expect(signals.cancelledUsers, ['user-a']);
  });

  test('Realtime signal được debounce rồi gọi full sync', () async {
    final fixture = _SyncBlocFixture();
    addTearDown(fixture.close);

    fixture.authBloc.add(AuthCheckRequested());
    await _waitUntil(() => fixture.synchronizer.calls == 1);
    expect(fixture.signals.watchedUsers, ['user-a']);

    fixture.signals.emit('user-a', AccountSyncSignal.changed);
    fixture.signals.emit('user-a', AccountSyncSignal.changed);
    fixture.signals.emit('user-a', AccountSyncSignal.connected);

    await _waitUntil(() => fixture.synchronizer.calls == 2);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(fixture.synchronizer.calls, 2);
  });

  test('đổi user hủy topic cũ và signal cũ không chạy sync', () async {
    final fixture = _SyncBlocFixture();
    addTearDown(fixture.close);

    fixture.authBloc.add(AuthCheckRequested());
    await _waitUntil(() => fixture.synchronizer.calls == 1);
    fixture.authRepository.current = const UserEntity(
      id: 'user-b',
      email: 'other@example.test',
    );
    fixture.authBloc.add(AuthCheckRequested());
    await _waitUntil(() => fixture.synchronizer.calls == 2);

    expect(fixture.signals.watchedUsers, ['user-a', 'user-b']);
    expect(fixture.signals.cancelledUsers, ['user-a']);
    fixture.signals.emit('user-a', AccountSyncSignal.changed);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(fixture.synchronizer.calls, 2);
  });

  test(
    'Realtime error không đổi sync sang failure và manual retry còn chạy',
    () async {
      final fixture = _SyncBlocFixture();
      addTearDown(fixture.close);

      fixture.authBloc.add(AuthCheckRequested());
      await _waitUntil(() => fixture.synchronizer.calls == 1);
      fixture.signals.fail('user-a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fixture.syncBloc.state, isA<SyncReady>());

      fixture.syncBloc.add(const SyncNowRequested());
      await _waitUntil(() => fixture.synchronizer.calls == 2);
      expect(fixture.syncBloc.state, isA<SyncReady>());
    },
  );
}

class _SyncBlocFixture {
  _SyncBlocFixture()
    : authRepository = _AuthRepository(),
      accountRepository = _AccountRepository(),
      synchronizer = _Synchronizer(),
      signals = _SignalRepository() {
    authBloc = AuthBloc(authRepository);
    accountsBloc = AccountsBloc(
      getAccounts: GetAccounts(accountRepository),
      addAccount: AddAccount(accountRepository),
      deleteAccount: DeleteAccount(accountRepository),
      updateAccount: UpdateAccount(accountRepository),
      importAccounts: ImportAccounts(accountRepository),
    );
    syncBloc = SyncBloc(synchronizer, signals, authBloc, accountsBloc);
  }

  final _AuthRepository authRepository;
  final _AccountRepository accountRepository;
  final _Synchronizer synchronizer;
  final _SignalRepository signals;
  late final AuthBloc authBloc;
  late final AccountsBloc accountsBloc;
  late final SyncBloc syncBloc;

  Future<void> close() async {
    await syncBloc.close();
    await accountsBloc.close();
    await authBloc.close();
    await signals.close();
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw TestFailure('Điều kiện async không hoàn tất.');
}

class _Synchronizer implements AccountSynchronizer {
  int calls = 0;

  @override
  Future<Either<Failure, AccountSyncResult>> call() async {
    calls++;
    return Right(
      AccountSyncCompleted(
        completedAt: DateTime.utc(2026, 8, 4),
        uploadedCount: 0,
        downloadedCount: 0,
        deletedCount: 0,
      ),
    );
  }
}

class _SignalRepository implements AccountSyncSignalRepository {
  final List<String> watchedUsers = [];
  final List<String> cancelledUsers = [];
  final Map<String, StreamController<AccountSyncSignal>> _controllers = {};

  @override
  Stream<AccountSyncSignal> watch({required String userId}) {
    watchedUsers.add(userId);
    late final StreamController<AccountSyncSignal> controller;
    controller = StreamController<AccountSyncSignal>(
      onCancel: () => cancelledUsers.add(userId),
    );
    _controllers[userId] = controller;
    return controller.stream;
  }

  void emit(String userId, AccountSyncSignal signal) {
    final controller = _controllers[userId];
    if (controller != null && controller.hasListener) controller.add(signal);
  }

  void fail(String userId) {
    final controller = _controllers[userId];
    if (controller != null && controller.hasListener) {
      controller.addError(StateError('TEST ONLY signal error'));
    }
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      if (!controller.isClosed) await controller.close();
    }
  }
}

class _AuthRepository implements AuthRepository {
  UserEntity? current = const UserEntity(
    id: 'user-a',
    email: 'user@example.test',
  );

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

class _AccountRepository implements AuthenticatorRepository {
  final List<AuthenticatorAccount> accounts = [];

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) async {
    final account = AuthenticatorAccount(
      id: '11111111-1111-4111-8111-111111111111',
      issuer: issuer,
      accountName: accountName,
      secretKey: secretKey,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
    accounts.add(account);
    return Right(account);
  }

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) async =>
      const Right(unit);

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List.unmodifiable(accounts));

  @override
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) async =>
      const Right(AccountImportSummary(importedCount: 0, duplicateCount: 0));

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> accounts,
  ) async => const Right(unit);

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) async => Right(account);

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async => const Right(unit);
}
