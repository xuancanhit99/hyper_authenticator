import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/chrome_extension/presentation/chrome_extension_add_account_page.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/router/app_routes.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/login_page.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/register_page.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/update_password_page.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/accounts_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/edit_account_page.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/features/settings/presentation/pages/settings_page.dart';

class ChromeExtensionRouter {
  ChromeExtensionRouter(this._authBloc, this._appConfig);

  final AuthBloc _authBloc;
  final AppConfig _appConfig;
  final _rootNavigatorKey = GlobalKey<NavigatorState>();
  late final _refresh = _AuthRouterRefresh(_authBloc.stream);
  late final GoRouter _router = _buildRouter();

  GoRouter config() => _router;

  GoRouter _buildRouter() => GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: _refresh,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.updatePassword,
        builder: (_, _) => const UpdatePasswordPage(),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => NoTransitionPage(
          key: state.pageKey,
          child: MainNavigationPage(navigationShell: navigationShell),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.main,
                builder: (_, _) => const AccountsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (_, _) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.addAccount,
        builder: (_, _) => const ChromeExtensionAddAccountPage(),
      ),
      GoRoute(
        path: AppRoutes.editAccount,
        builder: (context, state) {
          final account = state.extra;
          if (account is AuthenticatorAccount) {
            return EditAccountPage(account: account);
          }
          return const Scaffold(
            body: Center(child: Text('Không tìm thấy dữ liệu tài khoản.')),
          );
        },
      ),
    ],
    redirect: (_, state) {
      final location = state.matchedLocation;
      final isPublicAuthRoute =
          location == AppRoutes.login ||
          location == AppRoutes.register ||
          location == AppRoutes.forgotPassword ||
          location == AppRoutes.updatePassword;
      if (!isPublicAuthRoute) return null;
      if (!_appConfig.cloudEnabled || _authBloc.state is AuthAuthenticated) {
        return AppRedirectPolicy.authenticatedDestination(
          returnTo: state.uri.queryParameters['returnTo'],
        );
      }
      return null;
    },
    errorBuilder: (_, state) =>
        const Scaffold(body: Center(child: Text('Không tìm thấy trang này.'))),
  );
}

class _AuthRouterRefresh extends ChangeNotifier {
  _AuthRouterRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
