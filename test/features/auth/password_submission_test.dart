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

void main() {
  const email = 'synthetic@example.invalid';
  const passwords = {
    'leading space': ' SYNTHETIC_password',
    'trailing space': 'SYNTHETIC_password ',
    'Unicode and combining marks': '  Mật_khẩu_🔐_e\u0301  ',
    'Unicode boundary whitespace': '\u00a0SYNTHETIC_password\u3000',
  };

  Future<_PasswordRepository> pumpPage(
    WidgetTester tester,
    String initialLocation, {
    String? existingPassword,
  }) async {
    final repository = _PasswordRepository(existingPassword);
    final bloc = AuthBloc(repository);
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Accounts home')),
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
      await bloc.close();
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> submitLogin(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextFormField).at(0), ' $email ');
    await tester.enterText(find.byType(TextFormField).at(1), password);
    final submit = find.widgetWithText(ElevatedButton, 'Đăng nhập');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  for (final entry in passwords.entries) {
    testWidgets('login preserves ${entry.key}', (tester) async {
      final repository = await pumpPage(
        tester,
        '/login',
        existingPassword: entry.value,
      );

      await submitLogin(tester, entry.value);

      expect(repository.loginPassword == entry.value, isTrue);
      expect(repository.loginEmail, email);
      expect(find.text('Accounts home'), findsOneWidget);
    });

    testWidgets('register then login preserves ${entry.key}', (tester) async {
      final repository = await pumpPage(tester, '/register');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), ' $email ');
      await tester.enterText(fields.at(1), entry.value);
      await tester.enterText(fields.at(2), entry.value);
      final submit = find.widgetWithText(ElevatedButton, 'Đăng ký');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(repository.registeredPassword == entry.value, isTrue);
      expect(repository.registeredEmail, email);
      expect(find.byType(LoginPage), findsOneWidget);

      await submitLogin(tester, entry.value);

      expect(repository.loginPassword == entry.value, isTrue);
      expect(find.text('Accounts home'), findsOneWidget);
    });

    testWidgets('password update then login preserves ${entry.key}', (
      tester,
    ) async {
      final repository = await pumpPage(tester, '/update-password');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), entry.value);
      await tester.enterText(fields.at(1), entry.value);
      final submit = find.widgetWithText(ElevatedButton, 'Cập nhật mật khẩu');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(repository.updatedPassword == entry.value, isTrue);
      expect(find.byType(LoginPage), findsOneWidget);

      await submitLogin(tester, entry.value);

      expect(repository.loginPassword == repository.updatedPassword, isTrue);
      expect(find.text('Accounts home'), findsOneWidget);
    });
  }
}

class _PasswordRepository implements AuthRepository {
  _PasswordRepository(this._password);

  static const _user = UserEntity(
    id: '00000000-0000-4000-8000-000000000001',
    email: 'synthetic@example.invalid',
  );

  String? _password;
  String? registeredEmail;
  String? registeredPassword;
  String? updatedPassword;
  String? loginEmail;
  String? loginPassword;
  UserEntity? _currentUser;

  @override
  UserEntity? get currentUserEntity => _currentUser;

  @override
  Stream<UserEntity?> get authEntityChanges => const Stream.empty();

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(_currentUser);

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    loginEmail = email;
    loginPassword = password;
    if (password != _password) {
      return const Left(ServerFailure('Synthetic credential mismatch.'));
    }
    _currentUser = _user;
    return const Right(_user);
  }

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    registeredEmail = email;
    registeredPassword = password;
    _password = password;
    // Model email confirmation: registration does not create a session.
    return const Right(_user);
  }

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async {
    updatedPassword = newPassword;
    _password = newPassword;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> signInWithGoogle() async => const Right(null);

  @override
  Future<Either<Failure, void>> signOut() async => const Right(null);
}
