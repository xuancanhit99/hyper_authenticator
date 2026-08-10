import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowRemoteMutation = bool.fromEnvironment(
  'ALLOW_ACCOUNT_SYNC_REMOTE_TEST_MUTATION',
);
const _testEmail = String.fromEnvironment('ACCOUNT_SYNC_TEST_EMAIL');
const _testPassword = String.fromEnvironment('ACCOUNT_SYNC_TEST_PASSWORD');
const _testAccount = AuthenticatorAccount(
  id: 'auth-session-smoke-account',
  issuer: 'TEST_ONLY Auth Session',
  accountName: 'local-vault@example.invalid',
  secretKey: 'JBSWY3DPEHPK3PXP',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'đăng nhập/đăng xuất qua UI và giữ nguyên local vault',
    (tester) async {
      expect(
        _allowRemoteMutation,
        isTrue,
        reason: 'Chỉ chạy với isolated remote user do operator harness tạo.',
      );
      expect(_testEmail, isNotEmpty);
      expect(_testPassword, isNotEmpty);

      final preferences = await SharedPreferences.getInstance();
      AuthenticatorRepository? localRepository;
      AuthRepository? authRepository;
      AuthBloc? authBloc;

      try {
        await preferences.setBool('biometric_enabled', false);
        await app.main();
        await _pumpUntil(tester, find.byKey(MainNavigationPage.settingsTabKey));

        localRepository = di.sl<AuthenticatorRepository>();
        authRepository = di.sl<AuthRepository>();
        authBloc = di.sl<AuthBloc>();
        _right(
          await localRepository.replaceAccounts(const [_testAccount]),
          'seed-local-vault',
        );

        await tester.tap(find.byKey(MainNavigationPage.settingsTabKey).last);
        await _tapVisible(tester, find.text('Đăng nhập để đồng bộ'));
        await _pumpUntil(tester, find.text('Chào mừng bạn trở lại!'));

        final emailField = find.widgetWithText(TextFormField, 'Email');
        final passwordField = find.widgetWithText(TextFormField, 'Mật khẩu');
        await tester.enterText(emailField, _testEmail);
        await tester.enterText(passwordField, _testPassword);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 200));
        final loginButton = find
            .widgetWithText(ElevatedButton, 'Đăng nhập')
            .hitTestable();
        await _pumpUntil(tester, loginButton);
        await tester.tap(loginButton);

        await _pumpUntilAuthState(
          tester,
          authBloc,
          (state) => state is AuthAuthenticated,
        );
        await _pumpUntil(tester, find.text('Cài đặt'));
        await _pumpUntil(tester, find.text(_testEmail));
        expect(authBloc.state, isA<AuthAuthenticated>());
        _phase('ui-sign-in-verified');

        final logoutTile = find.widgetWithText(ListTile, 'Đăng xuất');
        await _tapVisible(tester, logoutTile);
        await _pumpUntil(tester, find.text('Xác nhận đăng xuất'));
        await tester.tap(
          find.widgetWithText(FilledButton, 'Đăng xuất').hitTestable(),
        );
        await _pumpUntilAuthState(
          tester,
          authBloc,
          (state) => state is AuthUnauthenticated,
        );
        await _pumpUntil(tester, find.text('Đăng nhập để đồng bộ'));

        expect(authBloc.state, isA<AuthUnauthenticated>());
        expect(
          _right(await localRepository.getAccounts(), 'read-local-vault'),
          const [_testAccount],
        );
        _phase('ui-sign-out-preserved-local-vault');
      } finally {
        await authRepository?.signOut();
        if (localRepository != null) {
          _right(
            await localRepository.replaceAccounts(const []),
            'cleanup-local-vault',
          );
        }
        await preferences.setBool('biometric_enabled', false);
        _phase('finally-cleanup-complete');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

T _right<T>(Either<Failure, T> result, String operation) => result.fold(
  (failure) =>
      throw TestFailure('$operation thất bại (${failure.runtimeType}).'),
  (value) => value,
);

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timeout khi chờ widget: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _pumpUntil(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final target = finder.hitTestable();
  expect(target, findsOneWidget);
  await tester.tap(target);
}

Future<void> _pumpUntilAuthState(
  WidgetTester tester,
  AuthBloc bloc,
  bool Function(AuthState state) matches, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!matches(bloc.state)) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(
        'Timeout khi chờ AuthBloc state; hiện tại ${bloc.state.runtimeType}.',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

void _phase(String name) {
  debugPrint('AUTH_SESSION_DEVICE_PHASE=$name');
}
