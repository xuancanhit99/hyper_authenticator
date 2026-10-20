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

void main() {
  for (final registration in [false, true]) {
    testWidgets(
      'Google ${registration ? 'register' : 'login'} không yêu cầu nhập email/password',
      (tester) async {
        final repository = _OAuthRepository();
        final bloc = AuthBloc(repository);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  registration ? const RegisterPage() : const LoginPage(),
            ),
          ],
        );
        addTearDown(router.dispose);
        addTearDown(bloc.close);
        await tester.pumpWidget(
          BlocProvider.value(
            value: bloc,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.widgetWithText(
          OutlinedButton,
          'Tiếp tục với Google',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(repository.calls, 1);
        expect(find.text('Nhập email.'), findsNothing);
        expect(bloc.state, isA<AuthGoogleRedirectStarted>());
      },
    );
  }
}

class _OAuthRepository implements AuthRepository {
  int calls = 0;
  @override
  UserEntity? get currentUserEntity => null;
  @override
  Stream<UserEntity?> get authEntityChanges => const Stream.empty();
  @override
  Future<Either<Failure, void>> signInWithGoogle() async {
    calls++;
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
