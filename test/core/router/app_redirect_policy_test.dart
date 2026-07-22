import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';

void main() {
  test('app lock bootstrap giữ lại deep link Settings an toàn', () {
    final startupRedirect = AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: LocalAuthInitial(),
      location: AppRoutes.settings,
    );
    final settingsRedirect = AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: LocalAuthUnavailable(),
      location: AppRoutes.startup,
      returnTo: AppRoutes.settings,
    );

    expect(startupRedirect, '/startup?returnTo=%2Fsettings');
    expect(settingsRedirect, AppRoutes.settings);
  });

  test('app lock không chấp nhận external return URL', () {
    final redirect = AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: LocalAuthSuccess(),
      location: AppRoutes.lockScreen,
      returnTo: 'https://example.invalid/phishing',
    );

    expect(redirect, AppRoutes.main);
  });

  test(
    'unauthenticated user được vào local vault khi app lock unavailable',
    () {
      final redirect = AppRedirectPolicy.redirect(
        authState: AuthUnauthenticated(),
        localAuthState: LocalAuthUnavailable(),
        location: AppRoutes.main,
      );

      expect(redirect, isNull);
    },
  );

  test('app lock fail closed không phụ thuộc Supabase session', () {
    final required = AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: LocalAuthRequired(),
      location: AppRoutes.main,
    );
    final errored = AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: const LocalAuthError('TEST_ONLY'),
      location: AppRoutes.addAccount,
    );

    expect(required, AppRoutes.lockScreen);
    expect(errored, AppRoutes.lockScreen);
  });

  test('public auth route không bị app lock redirect', () {
    final redirect = AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: LocalAuthRequired(),
      location: AppRoutes.forgotPassword,
    );

    expect(redirect, isNull);
  });

  test('authenticated user không quay lại login', () {
    const user = UserEntity(
      id: 'TEST_ONLY_USER',
      email: 'user@example.invalid',
    );
    final redirect = AppRedirectPolicy.redirect(
      authState: const AuthAuthenticated(user),
      localAuthState: LocalAuthSuccess(),
      location: AppRoutes.login,
    );
    final settingsRedirect = AppRedirectPolicy.redirect(
      authState: const AuthAuthenticated(user),
      localAuthState: LocalAuthSuccess(),
      location: AppRoutes.login,
      returnTo: AppRoutes.settings,
    );
    final externalRedirect = AppRedirectPolicy.redirect(
      authState: const AuthAuthenticated(user),
      localAuthState: LocalAuthSuccess(),
      location: AppRoutes.login,
      returnTo: 'https://example.invalid/phishing',
    );

    expect(redirect, AppRoutes.main);
    expect(settingsRedirect, AppRoutes.settings);
    expect(externalRedirect, AppRoutes.main);
  });
}
