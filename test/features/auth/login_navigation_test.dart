import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/login_page.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/register_page.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/update_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const user = UserEntity(
    id: '00000000-0000-4000-8000-000000000001',
    email: 'test-only@example.invalid',
    name: 'TEST_ONLY User',
  );

  late AuthBloc authBloc;
  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester, {
    required String initialLocation,
    Size? viewSize,
    TextScaler? textScaler,
  }) async {
    if (viewSize != null) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewSize;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    SharedPreferences.setMockInitialValues({});
    authBloc = AuthBloc(
      const _SuccessfulAuthRepository(user),
      await SharedPreferences.getInstance(),
    );
    router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Accounts home')),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('Settings host')),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
        GoRoute(
          path: '/update-password',
          builder: (_, _) => const UpdatePasswordPage(),
        ),
      ],
    );
    addTearDown(() async {
      router.dispose();
      await authBloc.close();
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(
          routerConfig: router,
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void signIn() {
    authBloc.add(
      const AuthSignInRequested(
        email: 'test-only@example.invalid',
        password: 'TEST_ONLY_PASSWORD',
        rememberMe: false,
      ),
    );
  }

  testWidgets('đăng nhập trực tiếp rời Login về Accounts', (tester) async {
    await pumpApp(tester, initialLocation: '/login');

    expect(find.text('Chào mừng bạn trở lại!'), findsOneWidget);
    expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
    expect(find.text('Ghi nhớ đăng nhập'), findsOneWidget);
    expect(find.text('Quên mật khẩu?'), findsOneWidget);
    expect(find.text('Welcome Back!'), findsNothing);

    signIn();
    await tester.pumpAndSettle();

    expect(find.text('Accounts home'), findsOneWidget);
    expect(find.text('Chào mừng bạn trở lại!'), findsNothing);
  });

  testWidgets('đăng nhập được push từ Settings quay lại Settings', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: '/settings');
    router.push('/login?returnTo=%2Fsettings');
    await tester.pumpAndSettle();

    signIn();
    await tester.pumpAndSettle();

    expect(find.text('Settings host'), findsOneWidget);
    expect(find.text('Chào mừng bạn trở lại!'), findsNothing);
  });

  testWidgets(
    'auth có accessible name, tap target và không overflow ở text scale 200%',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(
        tester,
        initialLocation: '/login',
        viewSize: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
      );

      expect(find.byTooltip('Hiện mật khẩu'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      router.go('/register');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hiện mật khẩu'), findsNWidgets(2));

      router.go('/update-password');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hiện mật khẩu'), findsNWidgets(2));
      semantics.dispose();
    },
  );

  test('auth event/state string redact password và user identity', () {
    const email = 'sensitive@example.invalid';
    const password = 'TEST_ONLY_SENSITIVE_PASSWORD';
    const sensitiveUser = UserEntity(
      id: '00000000-0000-4000-8000-000000000002',
      email: email,
      name: 'TEST_ONLY Sensitive User',
    );
    final values = <Object>[
      const AuthSignInRequested(
        email: email,
        password: password,
        rememberMe: true,
      ),
      const AuthSignUpRequested(
        name: 'TEST_ONLY Sensitive User',
        email: email,
        password: password,
      ),
      const AuthRecoverPasswordRequested(email),
      const AuthPasswordUpdateRequested(newPassword: password),
      const AuthInitial(rememberedEmail: email, rememberedMeState: true),
      const AuthAuthenticated(sensitiveUser),
    ];

    for (final value in values) {
      expect(value.toString(), isNot(contains(email)));
      expect(value.toString(), isNot(contains(password)));
      expect(value.toString(), contains('[REDACTED]'));
    }
  });
}

class _SuccessfulAuthRepository implements AuthRepository {
  final UserEntity user;

  const _SuccessfulAuthRepository(this.user);

  @override
  UserEntity? get currentUserEntity => user;

  @override
  Stream<UserEntity?> get authEntityChanges => const Stream.empty();

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(user);

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async => Right(user);

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name,
    required String email,
    required String password,
  }) async => Right(user);

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> revokeOtherSessions() async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> signOut() async => const Right(null);

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      const Right(null);
}
