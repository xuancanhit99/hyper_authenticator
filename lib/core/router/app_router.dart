// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Import LocalAuthBloc
import 'package:hyper_authenticator/features/auth/presentation/pages/login_page.dart'; // Renamed auth_page to login_page
import 'package:hyper_authenticator/features/auth/presentation/pages/register_page.dart'; // Added import
import 'package:hyper_authenticator/features/auth/presentation/pages/forgot_password_page.dart'; // Added import
import 'package:hyper_authenticator/features/auth/presentation/pages/update_password_page.dart'; // Added import
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/edit_account_page.dart'; // Added import for EditAccountPage
import 'package:hyper_authenticator/features/authenticator/presentation/pages/lock_screen_page.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart'; // Added import for AuthenticatorAccount
import 'package:hyper_authenticator/features/authenticator/presentation/pages/accounts_page.dart';
import 'package:hyper_authenticator/features/settings/presentation/pages/settings_page.dart';
// import 'package:hyper_authenticator/injection_container.dart'; // Not directly needed here

// --- Define Route Paths ---
class AppRoutes {
  static const startup = '/startup';
  static const login = '/login';
  static const main = '/'; // Main screen (wrapper with bottom nav)
  static const settings = '/settings';
  static const addAccount = '/add-account';
  static const lockScreen = '/lock-screen';
  static const register = '/register'; // Added
  static const forgotPassword = '/forgot-password'; // Added
  static const updatePassword =
      '/update-password'; // Added for deep link handling
  static const editAccount = '/edit-account'; // Added for EditAccountPage
}

/// Pure redirect policy so offline-vault and app-lock behavior can be tested
/// without constructing the widget tree.
class AppRedirectPolicy {
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

  static String authenticatedDestination({String? returnTo}) =>
      _safeMainReturnTo(returnTo) ?? AppRoutes.main;

  static String? _safeMainReturnTo(String? candidate) {
    return switch (candidate) {
      AppRoutes.main => AppRoutes.main,
      AppRoutes.settings => AppRoutes.settings,
      _ => null,
    };
  }
}

// Helper class to trigger GoRouter refresh on multiple Bloc stream changes
class CombinedAuthRefreshStream extends ChangeNotifier {
  late final List<StreamSubscription<dynamic>> _subscriptions;

  CombinedAuthRefreshStream(List<Stream<dynamic>> streams) {
    notifyListeners(); // Notify initially
    _subscriptions = streams
        .map(
          (stream) => stream
              .asBroadcastStream() // Ensure streams are broadcast streams
              .listen((_) => notifyListeners()),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}

class AppRouter {
  final AuthBloc authBloc;
  final LocalAuthBloc localAuthBloc;
  final AppConfig appConfig;
  final _rootNavigatorKey = GlobalKey<NavigatorState>();

  AppRouter(this.authBloc, this.localAuthBloc, this.appConfig);

  late final GoRouter _router = _buildRouter();

  static String get loginPath => AppRoutes.login;

  GoRouter config() => _router;

  GoRouter _buildRouter() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      // Chỉ lắng nghe AuthBloc để refresh redirect
      // Listen to both Blocs for refresh
      refreshListenable: CombinedAuthRefreshStream([
        authBloc.stream,
        localAuthBloc.stream,
      ]),
      routes: [
        // Public route
        GoRoute(
          path: AppRoutes.login,
          name: AppRoutes.login, // Use name for easier navigation if needed
          builder: (context, state) => const LoginPage(), // Existing Login Page
        ),
        // --- New Auth Routes ---
        GoRoute(
          path: AppRoutes.register,
          name: AppRoutes.register,
          builder: (context, state) => const RegisterPage(),
        ),
        GoRoute(
          path: AppRoutes.forgotPassword,
          name: AppRoutes.forgotPassword,
          builder: (context, state) => const ForgotPasswordPage(),
        ),
        GoRoute(
          path: AppRoutes.updatePassword,
          name: AppRoutes.updatePassword,
          // This page might receive parameters from deep link in the future
          builder: (context, state) => const UpdatePasswordPage(),
        ),
        StatefulShellRoute.indexedStack(
          // The shell owns a GlobalKey internally. A default page transition
          // can briefly keep two shell pages alive when auth-lock redirects
          // happen in quick succession (for example during lifecycle changes),
          // which triggers Flutter's duplicate GlobalKey assertion. Tab
          // switching keeps the native NavigationBar animation below.
          pageBuilder: (context, state, navigationShell) => NoTransitionPage(
            key: state.pageKey,
            child: MainNavigationPage(navigationShell: navigationShell),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.main,
                  name: AppRoutes.main,
                  builder: (context, state) => const AccountsPage(),
                  routes: [
                    // Keep bootstrap and lock overlays in the shell match
                    // list, but render them on the root navigator so the
                    // bottom navigation is covered and the shell is not
                    // destroyed/re-entered during lifecycle redirects.
                    GoRoute(
                      path: 'startup',
                      name: AppRoutes.startup,
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    GoRoute(
                      path: 'lock-screen',
                      name: AppRoutes.lockScreen,
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => const LockScreenPage(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.settings,
                  name: AppRoutes.settings,
                  builder: (context, state) => const SettingsPage(),
                ),
              ],
            ),
          ],
        ),
        // Add Account Route (protected by redirect)
        GoRoute(
          path: AppRoutes.addAccount,
          name: AppRoutes.addAccount,
          builder: (context, state) => const AddAccountPage(),
        ),
        // --- End New Auth Routes ---
        // Edit Account Route (protected by redirect)
        GoRoute(
          path: AppRoutes.editAccount,
          name: AppRoutes.editAccount,
          builder: (context, state) {
            AuthenticatorAccount? account;
            if (state.extra is AuthenticatorAccount) {
              account = state.extra as AuthenticatorAccount?;
            } else if (state.extra is Map<String, dynamic>) {
              // Attempt to deserialize from Map if it's not already an AuthenticatorAccount
              // This can happen when the app resumes and go_router restores state.
              try {
                account = AuthenticatorAccount.fromJson(
                  state.extra as Map<String, dynamic>,
                );
              } catch (_) {
                // Handle error, perhaps redirect or show an error page
              }
            }

            if (account == null) {
              // Handle error or redirect if account is not passed or deserialization fails
              // For now, returning a simple error page or redirecting to main
              // This should ideally not happen if navigation is done correctly
              return Scaffold(
                appBar: AppBar(title: const Text('Lỗi')),
                body: const Center(
                  child: Text('Không tìm thấy dữ liệu tài khoản để chỉnh sửa.'),
                ),
              );
            }
            return EditAccountPage(account: account);
          },
        ),
      ],

      // --- REDIRECT LOGIC (Simplified, based on original working version) ---
      redirect: (BuildContext context, GoRouterState state) {
        return AppRedirectPolicy.redirect(
          authState: authBloc.state,
          localAuthState: localAuthBloc.state,
          location: state.matchedLocation,
          returnTo: state.uri.queryParameters['returnTo'],
          cloudEnabled: appConfig.cloudEnabled,
        );
      },
      errorBuilder: (context, state) => Scaffold(
        body: Center(child: Text('Không tìm thấy trang: ${state.error}')),
      ),
    );
  }
}
