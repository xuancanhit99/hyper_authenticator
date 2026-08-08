import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';

/// Route names shared by the native/Web router and the Chrome Extension
/// router. Keeping this contract independent of a concrete router prevents
/// extension builds from importing mobile-only QR scanner code.
abstract final class AppRoutes {
  static const startup = '/startup';
  static const login = '/login';
  static const main = '/';
  static const settings = '/settings';
  static const addAccount = '/add-account';
  static const lockScreen = '/lock-screen';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const updatePassword = '/update-password';
  static const editAccount = '/edit-account';
  static const exportAccounts = '/export-accounts';
}

/// Pure redirect policy for the primary Flutter application.
///
/// The Chrome Extension owns a smaller policy because it intentionally does
/// not expose OS app lock or protected QR export in its first release.
abstract final class AppRedirectPolicy {
  static String? redirect({
    required AuthState authState,
    required LocalAuthState localAuthState,
    required String location,
    String? returnTo,
    bool cloudEnabled = true,
  }) {
    final isLogin = location == AppRoutes.login;
    final isRegister = location == AppRoutes.register;
    final isForgotPassword = location == AppRoutes.forgotPassword;
    final isUpdatePassword = location == AppRoutes.updatePassword;
    final isStartup = location == AppRoutes.startup;
    final isLockScreen = location == AppRoutes.lockScreen;
    final isPublicAuthRoute =
        isLogin || isRegister || isForgotPassword || isUpdatePassword;

    if (isPublicAuthRoute) {
      if (!cloudEnabled) {
        return authenticatedDestination(returnTo: returnTo);
      }
      if (authState is AuthAuthenticated && (isLogin || isRegister)) {
        return authenticatedDestination(returnTo: returnTo);
      }
      return null;
    }

    if (localAuthState is LocalAuthInitial) {
      return isStartup ? null : _routeWithReturnTo(AppRoutes.startup, location);
    }

    if (localAuthState is LocalAuthRequired ||
        localAuthState is LocalAuthError) {
      return isLockScreen
          ? null
          : _routeWithReturnTo(
              AppRoutes.lockScreen,
              _safeMainReturnTo(returnTo) ?? location,
            );
    }

    if (localAuthState is LocalAuthSuccess && (isStartup || isLockScreen)) {
      return _safeMainReturnTo(returnTo) ?? AppRoutes.main;
    }

    return null;
  }

  static String authenticatedDestination({String? returnTo}) =>
      _safeMainReturnTo(returnTo) ?? AppRoutes.main;

  static String _routeWithReturnTo(String route, String candidate) {
    final safeReturnTo = _safeMainReturnTo(candidate);
    if (safeReturnTo == null || safeReturnTo == AppRoutes.main) {
      return route;
    }
    return Uri(
      path: route,
      queryParameters: {'returnTo': safeReturnTo},
    ).toString();
  }

  static String? _safeMainReturnTo(String? candidate) {
    return switch (candidate) {
      AppRoutes.main => AppRoutes.main,
      AppRoutes.settings => AppRoutes.settings,
      _ => null,
    };
  }
}
