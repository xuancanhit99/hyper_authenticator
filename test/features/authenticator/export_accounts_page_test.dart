import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/sensitive_action_authenticator.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/export_accounts_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const account = AuthenticatorAccount(
    id: 'export-account',
    issuer: 'TEST_ONLY Issuer',
    accountName: 'user@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP',
  );
  const customAccount = AuthenticatorAccount(
    id: 'custom-account',
    issuer: 'TEST_ONLY Custom',
    accountName: 'custom@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP',
    algorithm: 'SHA512',
    digits: 7,
    period: 45,
  );

  testWidgets('chỉ hiện QR sau fresh auth và xóa khi app vào background', (
    tester,
  ) async {
    final authenticator = _FakeSensitiveActionAuthenticator(
      SensitiveActionAuthenticationResult.success,
    );
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: authenticator,
            platformSupported: true,
            sessionDuration: const Duration(seconds: 60),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    final accountTile = find.byKey(const Key('export-account-export-account'));
    await tester.tap(accountTile);
    await tester.pump();
    final exportButton = find.byKey(const Key('authenticate-and-export'));
    await tester.tap(exportButton);
    await tester.pump();

    expect(authenticator.calls, 1);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.bySemanticsLabel('Mã QR export Google Authenticator, phần 1 trên 1'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byType(Scaffold)).toString(),
      isNot(contains(account.secretKey)),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('không còn ở foreground'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancel không tạo payload và báo trạng thái an toàn', (
    tester,
  ) async {
    final authenticator = _FakeSensitiveActionAuthenticator(
      SensitiveActionAuthenticationResult.canceled,
    );
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: authenticator,
            platformSupported: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('export-account-export-account')),
    );
    await tester.tap(find.byKey(const Key('export-account-export-account')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('authenticate-and-export')),
    );
    await tester.tap(find.byKey(const Key('authenticate-and-export')));
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('chưa có QR nào được tạo'), findsOneWidget);
  });

  testWidgets('otpauth export tạo một QR mỗi account và giữ custom semantics', (
    tester,
  ) async {
    final bloc = _createBloc([account, customAccount]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: _FakeSensitiveActionAuthenticator(
              SensitiveActionAuthenticationResult.success,
            ),
            platformSupported: true,
            initialFormat: AccountExportFormat.otpauth,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final id in [account.id, customAccount.id]) {
      final finder = find.byKey(Key('export-account-$id'));
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(finder);
      await tester.pump();
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('authenticate-and-export')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('authenticate-and-export')));
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.bySemanticsLabel('Mã QR export chuẩn otpauth, tài khoản 1 trên 2'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('QR tiếp theo'));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Mã QR export chuẩn otpauth, tài khoản 2 trên 2'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byType(Scaffold)).toString(),
      isNot(contains(customAccount.secretKey)),
    );
  });

  testWidgets('đổi sang Google bỏ chọn account không tương thích', (
    tester,
  ) async {
    final bloc = _createBloc([customAccount]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: _FakeSensitiveActionAuthenticator(
              SensitiveActionAuthenticationResult.success,
            ),
            platformSupported: true,
            initialFormat: AccountExportFormat.otpauth,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final accountFinder = find.byKey(
      const Key('export-account-custom-account'),
    );
    await tester.scrollUntilVisible(
      accountFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(accountFinder);
    await tester.pump();
    expect(find.text('1 đã chọn'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('export-format-google')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('export-format-google')));
    await tester.pump();

    expect(find.text('0 đã chọn'), findsOneWidget);
    expect(
      find.textContaining('Google transfer yêu cầu period 30 giây'),
      findsOneWidget,
    );
  });

  testWidgets('auth success sau khi app vào background vẫn không tạo QR', (
    tester,
  ) async {
    final authenticator = _CompletingSensitiveActionAuthenticator();
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: authenticator,
            platformSupported: true,
            foregroundResumeTimeout: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('export-account-export-account')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('authenticate-and-export')));
    await tester.pump();

    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('export-account-export-account')),
    );
    expect(checkbox.onChanged, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    authenticator.complete(SensitiveActionAuthenticationResult.success);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('không còn ở foreground'), findsOneWidget);
  });

  testWidgets('auth hệ điều hành chờ lifecycle resumed trước khi tạo QR', (
    tester,
  ) async {
    final authenticator = _CompletingSensitiveActionAuthenticator();
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: authenticator,
            platformSupported: true,
            foregroundResumeTimeout: const Duration(seconds: 2),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('export-account-export-account')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('authenticate-and-export')));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    authenticator.complete(SensitiveActionAuthenticationResult.success);
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('account đổi trong lúc xác thực không xuất stale snapshot', (
    tester,
  ) async {
    final authenticator = _CompletingSensitiveActionAuthenticator();
    final repository = _MemoryAuthenticatorRepository([account]);
    final bloc = _createBlocWithRepository(repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: authenticator,
            platformSupported: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('export-account-export-account')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('authenticate-and-export')));
    await tester.pump();

    repository.accounts.clear();
    bloc.add(LoadAccounts());
    await tester.pump();
    await tester.pump();
    authenticator.complete(SensitiveActionAuthenticationResult.success);
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    expect(
      find.textContaining('Danh sách tài khoản vừa thay đổi'),
      findsOneWidget,
    );
  });

  testWidgets('QR tự hết hạn và bị xóa khỏi widget tree', (tester) async {
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: _FakeSensitiveActionAuthenticator(
              SensitiveActionAuthenticationResult.success,
            ),
            platformSupported: true,
            sessionDuration: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('export-account-export-account')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('authenticate-and-export')));
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('đã hết hạn'), findsOneWidget);
  });

  testWidgets('export UI không overflow ở viewport 320 và text scale 200%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ExportAccountsPage(
            authenticator: _FakeSensitiveActionAuthenticator(
              SensitiveActionAuthenticationResult.success,
            ),
            platformSupported: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);

    final accountTile = find.byKey(const Key('export-account-export-account'));
    await tester.scrollUntilVisible(
      accountTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<CheckboxListTile>(accountTile).onChanged!(true);
    await tester.pump();
    final exportButton = find.byKey(const Key('authenticate-and-export'));
    await tester.scrollUntilVisible(
      exportButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<FilledButton>(exportButton).onPressed!();
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform thiếu OS auth không có action export', (tester) async {
    final authenticator = _FakeSensitiveActionAuthenticator(
      SensitiveActionAuthenticationResult.success,
    );
    final bloc = _createBloc([account]);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp(
          home: ExportAccountsPage(
            authenticator: authenticator,
            platformSupported: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('chưa có ranh giới'), findsOneWidget);
    expect(find.byKey(const Key('authenticate-and-export')), findsNothing);
    expect(authenticator.calls, 0);
  });
}

AccountsBloc _createBloc(List<AuthenticatorAccount> accounts) {
  final repository = _MemoryAuthenticatorRepository(accounts);
  return _createBlocWithRepository(repository);
}

AccountsBloc _createBlocWithRepository(AuthenticatorRepository repository) {
  return AccountsBloc(
    getAccounts: GetAccounts(repository),
    addAccount: AddAccount(repository),
    deleteAccount: DeleteAccount(repository),
    updateAccount: UpdateAccount(repository),
    importAccounts: ImportAccounts(repository),
  )..add(LoadAccounts());
}

class _FakeSensitiveActionAuthenticator
    implements SensitiveActionAuthenticator {
  _FakeSensitiveActionAuthenticator(this.result);

  final SensitiveActionAuthenticationResult result;
  int calls = 0;

  @override
  Future<SensitiveActionAuthenticationResult> authenticateForExport() async {
    calls++;
    return result;
  }
}

class _CompletingSensitiveActionAuthenticator
    implements SensitiveActionAuthenticator {
  final Completer<SensitiveActionAuthenticationResult> _completer = Completer();

  void complete(SensitiveActionAuthenticationResult result) {
    _completer.complete(result);
  }

  @override
  Future<SensitiveActionAuthenticationResult> authenticateForExport() =>
      _completer.future;
}

class _MemoryAuthenticatorRepository implements AuthenticatorRepository {
  _MemoryAuthenticatorRepository(this.accounts);

  final List<AuthenticatorAccount> accounts;

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List.unmodifiable(accounts));

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
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> accounts,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAccount(AuthenticatorAccount account) =>
      throw UnimplementedError();
}
