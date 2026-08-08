// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/router/app_routes.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Import LocalAuthBloc
import 'package:hyper_authenticator/features/auth/presentation/pages/login_page.dart'; // Renamed auth_page to login_page
import 'package:hyper_authenticator/features/auth/presentation/pages/register_page.dart'; // Added import
import 'package:hyper_authenticator/features/auth/presentation/pages/forgot_password_page.dart'; // Added import
import 'package:hyper_authenticator/features/auth/presentation/pages/update_password_page.dart'; // Added import
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/edit_account_page.dart'; // Added import for EditAccountPage
import 'package:hyper_authenticator/features/authenticator/presentation/pages/export_accounts_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/lock_screen_page.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart'; // Added import for AuthenticatorAccount
import 'package:hyper_authenticator/features/authenticator/presentation/pages/accounts_page.dart';
import 'package:hyper_authenticator/features/settings/presentation/pages/settings_page.dart';
// import 'package:hyper_authenticator/injection_container.dart'; // Not directly needed here

export 'app_routes.dart';

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
        GoRoute(
          path: AppRoutes.exportAccounts,
          name: AppRoutes.exportAccounts,
          builder: (context, state) => const ExportAccountsPage(),
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
