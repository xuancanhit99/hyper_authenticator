import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/edit_account_page.dart';

const _account = AuthenticatorAccount(
  id: 'edit-route-account',
  issuer: 'TEST_ONLY Issuer',
  accountName: 'user@example.invalid',
  secretKey: 'JBSWY3DPEHPK3PXP',
  algorithm: 'SHA256',
  digits: 8,
  period: 45,
);

void main() {
  testWidgets('chỉ đóng edit route sau success đúng operation', (tester) async {
    final updateGate = Completer<void>();
    final repository = _MemoryAuthenticatorRepository(updateGate: updateGate);
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: accountsBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EditAccountPage(account: _account),
                  ),
                ),
                child: const Text('Mở form sửa test'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở form sửa test'));
    await tester.pumpAndSettle();

    accountsBloc.add(LoadAccounts());
    await tester.pumpAndSettle();
    expect(find.byType(EditAccountPage), findsOneWidget);
    expect(repository.updateCalls, 0);

    await tester.dragUntilVisible(
      find.byKey(EditAccountPage.submitButtonKey),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(EditAccountPage.submitButtonKey));
    await tester.pump();

    expect(repository.updateCalls, 1);
    expect(find.text('Đang lưu…'), findsOneWidget);
    final submitButton = tester.widget<ElevatedButton>(
      find.byKey(EditAccountPage.submitButtonKey),
    );
    expect(submitButton.onPressed, isNull);
    await tester.tap(find.byKey(EditAccountPage.submitButtonKey));
    await tester.pump();
    expect(repository.updateCalls, 1);

    updateGate.complete();
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.updatedAccount, _account);
    expect(find.byType(EditAccountPage), findsNothing);
    expect(find.text('Mở form sửa test'), findsOneWidget);
    expect(find.text('Đã cập nhật tài khoản.'), findsOneWidget);
  });

  testWidgets(
    'edit success ở GoRouter root trở về main thay vì pop page cuối',
    (tester) async {
      final repository = _MemoryAuthenticatorRepository();
      final accountsBloc = _accountsBloc(repository);
      final router = GoRouter(
        initialLocation: AppRoutes.editAccount,
        routes: [
          GoRoute(
            path: AppRoutes.main,
            builder: (_, _) => const Scaffold(body: Text('Main test route')),
          ),
          GoRoute(
            path: AppRoutes.editAccount,
            builder: (_, _) => const EditAccountPage(account: _account),
          ),
        ],
      );
      addTearDown(accountsBloc.close);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        BlocProvider.value(
          value: accountsBloc,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditAccountPage), findsOneWidget);

      await tester.dragUntilVisible(
        find.byKey(EditAccountPage.submitButtonKey),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(EditAccountPage.submitButtonKey));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(find.text('Main test route'), findsOneWidget);
      expect(find.text('Đã cập nhật tài khoản.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'update success không thuộc form hiện tại không đóng edit route',
    (tester) async {
      final repository = _MemoryAuthenticatorRepository();
      final accountsBloc = _accountsBloc(repository);
      addTearDown(accountsBloc.close);

      await tester.pumpWidget(
        BlocProvider.value(
          value: accountsBloc,
          child: const MaterialApp(home: EditAccountPage(account: _account)),
        ),
      );
      await tester.pumpAndSettle();

      accountsBloc.add(
        UpdateAccountRequested(account: _account, operationToken: Object()),
      );
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(find.byType(EditAccountPage), findsOneWidget);
      expect(find.text('Đã cập nhật tài khoản.'), findsNothing);
    },
  );

  testWidgets('edit route chỉ nhận success có đúng opaque operation token', (
    tester,
  ) async {
    final updateGate = Completer<void>();
    final repository = _MemoryAuthenticatorRepository(updateGate: updateGate);
    final accountsBloc = _ControllableAccountsBloc(repository);
    addTearDown(accountsBloc.close);

    await tester.pumpWidget(
      BlocProvider<AccountsBloc>.value(
        value: accountsBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EditAccountPage(account: _account),
                  ),
                ),
                child: const Text('Mở edit token test'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở edit token test'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(EditAccountPage.submitButtonKey),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(EditAccountPage.submitButtonKey));
    await tester.pump();

    final activeToken = accountsBloc.lastUpdateOperationToken;
    expect(activeToken, isNotNull);
    accountsBloc.emitForTest(
      AccountUpdateFailure(Object(), 'SHOULD_NOT_BE_RENDERED'),
    );
    await tester.pump();
    expect(find.byType(EditAccountPage), findsOneWidget);
    expect(find.textContaining('SHOULD_NOT_BE_RENDERED'), findsNothing);
    expect(find.text('Đang lưu…'), findsOneWidget);

    accountsBloc.emitForTest(AccountUpdateSuccess(Object()));
    await tester.pump();
    expect(find.byType(EditAccountPage), findsOneWidget);

    accountsBloc.emitForTest(AccountUpdateSuccess(activeToken!));
    await tester.pumpAndSettle();
    expect(find.byType(EditAccountPage), findsNothing);
    expect(find.text('Mở edit token test'), findsOneWidget);

    updateGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('update failure đúng token giữ form và cho phép thử lại', (
    tester,
  ) async {
    final repository = _MemoryAuthenticatorRepository(
      updateFailure: const StorageFailure('TEST_ONLY storage failure'),
    );
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: accountsBloc,
        child: const MaterialApp(home: EditAccountPage(account: _account)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(EditAccountPage.submitButtonKey),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(EditAccountPage.submitButtonKey));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(find.byType(EditAccountPage), findsOneWidget);
    expect(find.text('Lưu thay đổi'), findsOneWidget);
    expect(
      find.text('Không thể cập nhật tài khoản: TEST_ONLY storage failure'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(EditAccountPage.submitButtonKey))
          .onPressed,
      isNotNull,
    );
  });

  test('event/state mutation không lộ account hoặc secret khi stringify', () {
    const secret = 'JBSWY3DPEHPK3PXP';
    const identity = 'user@example.invalid';
    final operationToken = Object();
    final addEvent = AddAccountRequested(
      issuer: 'TEST_ONLY Issuer',
      accountName: identity,
      secretKey: secret,
      algorithm: 'SHA1',
      digits: 6,
      period: 30,
    );
    final updateEvent = UpdateAccountRequested(
      account: _account,
      operationToken: operationToken,
    );
    final updateSuccess = AccountUpdateSuccess(operationToken);
    final updateFailure = AccountUpdateFailure(
      operationToken,
      'TEST_ONLY failure',
    );
    final addParams = AddAccountParams(
      issuer: 'TEST_ONLY Issuer',
      accountName: identity,
      secretKey: secret,
      algorithm: 'SHA1',
      digits: 6,
      period: 30,
    );
    const updateParams = UpdateAccountParams(account: _account);

    for (final value in [
      _account,
      addEvent,
      addParams,
      updateEvent,
      updateParams,
      updateSuccess,
      updateFailure,
    ]) {
      expect(value.toString(), isNot(contains(secret)));
      expect(value.toString(), isNot(contains(identity)));
    }
    expect(updateEvent.toString(), contains('[REDACTED]'));
    expect(updateSuccess.toString(), contains('[OPAQUE]'));
    expect(updateFailure.toString(), contains('[OPAQUE]'));
    expect(updateFailure.toString(), isNot(contains('TEST_ONLY failure')));
  });
}

AccountsBloc _accountsBloc(AuthenticatorRepository repository) => AccountsBloc(
  getAccounts: GetAccounts(repository),
  addAccount: AddAccount(repository),
  deleteAccount: DeleteAccount(repository),
  updateAccount: UpdateAccount(repository),
);

class _ControllableAccountsBloc extends AccountsBloc {
  _ControllableAccountsBloc(AuthenticatorRepository repository)
    : super(
        getAccounts: GetAccounts(repository),
        addAccount: AddAccount(repository),
        deleteAccount: DeleteAccount(repository),
        updateAccount: UpdateAccount(repository),
      );

  Object? lastUpdateOperationToken;

  @override
  void onEvent(AccountsEvent event) {
    if (event is UpdateAccountRequested) {
      lastUpdateOperationToken = event.operationToken;
    }
    super.onEvent(event);
  }

  void emitForTest(AccountsState state) => emit(state);
}

class _MemoryAuthenticatorRepository implements AuthenticatorRepository {
  _MemoryAuthenticatorRepository({this.updateGate, this.updateFailure});

  final Completer<void>? updateGate;
  final Failure? updateFailure;
  int updateCalls = 0;
  AuthenticatorAccount? updatedAccount;

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      const Right([_account]);

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async {
    updateCalls++;
    updatedAccount = account;
    await updateGate?.future;
    if (updateFailure case final failure?) {
      return Left(failure);
    }
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> accounts,
  ) {
    throw UnimplementedError();
  }
}
