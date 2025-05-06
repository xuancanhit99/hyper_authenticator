// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
// import 'package:hyper_authenticator/injection_container.dart'; // Not directly needed here

// --- Define Route Paths ---
class AppRoutes {
  static const login = '/login';
  static const main = '/'; // Main screen (wrapper with bottom nav)
  static const addAccount = '/add-account';
  static const lockScreen = '/lock-screen';
  static const register = '/register'; // Added
  static const forgotPassword = '/forgot-password'; // Added
  static const updatePassword =
      '/update-password'; // Added for deep link handling
  static const editAccount = '/edit-account'; // Added for EditAccountPage
}

// Helper class to trigger GoRouter refresh on multiple Bloc stream changes
class CombinedAuthRefreshStream extends ChangeNotifier {
  late final List<StreamSubscription<dynamic>> _subscriptions;

  CombinedAuthRefreshStream(List<Stream<dynamic>> streams) {
    notifyListeners(); // Notify initially
    _subscriptions =
        streams
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
  final LocalAuthBloc localAuthBloc; // Add LocalAuthBloc dependency

  AppRouter(this.authBloc, this.localAuthBloc); // Update constructor

  static String get loginPath => AppRoutes.login;

  GoRouter config() {
    return GoRouter(
      initialLocation: AppRoutes.main, // Bắt đầu ở trang chính
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
        // Main App Shell Route (protected by redirect)
        GoRoute(
          path: AppRoutes.main, // '/'
          name: AppRoutes.main,
          builder: (context, state) => const MainNavigationPage(),
        ),
        // Add Account Route (protected by redirect)
        GoRoute(
          path: AppRoutes.addAccount,
          name: AppRoutes.addAccount,
          builder: (context, state) => const AddAccountPage(),
        ),
        // Lock Screen Route
        GoRoute(
          path: AppRoutes.lockScreen,
          name: AppRoutes.lockScreen,
          builder: (context, state) => const LockScreenPage(),
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
              } catch (e) {
                debugPrint(
                  'Error deserializing AuthenticatorAccount from Map: $e',
                );
                // Handle error, perhaps redirect or show an error page
              }
            }

            if (account == null) {
              // Handle error or redirect if account is not passed or deserialization fails
              // For now, returning a simple error page or redirecting to main
              // This should ideally not happen if navigation is done correctly
              return Scaffold(
                appBar: AppBar(title: const Text('Error')),
                body: const Center(
                  child: Text('Account data not found for editing.'),
                ),
              );
            }
            return EditAccountPage(account: account);
          },
        ),
      ],

      // --- REDIRECT LOGIC (Simplified, based on original working version) ---
      redirect: (BuildContext context, GoRouterState state) {
        final supabaseAuthState = authBloc.state;
        final localAuthState = localAuthBloc.state;
        final location = state.matchedLocation;

        final isGoingToLogin = location == AppRoutes.login;
        final isGoingToLockScreen = location == AppRoutes.lockScreen;
        // Add checks for other public routes
        final isGoingToRegister = location == AppRoutes.register;
        final isGoingToForgotPassword = location == AppRoutes.forgotPassword;
        // UpdatePassword might need special handling (only via deep link)
        // final isGoingToUpdatePassword = location == AppRoutes.updatePassword;

        // Added timestamp for better tracing
        final timestamp = DateTime.now().toIso8601String();
        debugPrint(
          "[$timestamp Redirect] Supabase State: ${supabaseAuthState.runtimeType}, LocalAuth State: ${localAuthState.runtimeType}, Location: $location",
        );

        // 1. Chờ Supabase Auth load xong
        if (supabaseAuthState is AuthInitial ||
            supabaseAuthState is AuthLoading) {
          debugPrint("[$timestamp Redirect] Waiting for Supabase Auth...");
          return null; // Wait for Supabase auth to settle
        }

        final isSupabaseAuthenticated = supabaseAuthState is AuthAuthenticated;

        // 2. Nếu CHƯA đăng nhập Supabase và KHÔNG ở trang Login -> Về Login
        // 2. If NOT Supabase authenticated and NOT going to an allowed public route -> Go Login
        // Allowed public routes: login, register, forgotPassword
        if (!isSupabaseAuthenticated &&
            !isGoingToLogin &&
            !isGoingToRegister &&
            !isGoingToForgotPassword) {
          debugPrint(
            "[$timestamp Redirect] Unauthenticated & not on allowed public route ($location) -> Go Login",
          );
          return AppRoutes.login;
        }

        // 3. Nếu ĐÃ đăng nhập Supabase và ĐANG ở trang Login -> Vào Main
        // 4. Nếu ĐÃ đăng nhập Supabase VÀ ĐANG ở trang Login -> Vào Main
        //    (Logic kiểm tra Local Auth sẽ chạy sau nếu cần khi đã ở Main hoặc Lock)
        if (isSupabaseAuthenticated && isGoingToLogin) {
          debugPrint(
            "[$timestamp Redirect] Authenticated & on Login -> Go Main",
          );
          return AppRoutes.main; // Redirect away from login immediately
        }

        // --- Local Authentication Checks (only if Supabase authenticated) ---
        if (isSupabaseAuthenticated) {
          // 5. Chờ Local Auth load xong (nếu cần)
          if (localAuthState is LocalAuthInitial) {
            debugPrint("[$timestamp Redirect] Waiting for Local Auth check...");
            // Dispatch check if not already done (though app.dart should do it)
            // localAuthBloc.add(CheckLocalAuth()); // Consider if needed here
            return null; // Wait
          }

          // 6. Nếu Local Auth YÊU CẦU và KHÔNG ở màn hình khóa -> Tới màn hình khóa
          if (localAuthState is LocalAuthRequired && !isGoingToLockScreen) {
            debugPrint(
              "[$timestamp Redirect] Local Auth Required & not on Lock Screen -> Go Lock Screen",
            );
            return AppRoutes.lockScreen;
          }

          // 7. Nếu Local Auth THÀNH CÔNG và ĐANG ở màn hình khóa -> Vào Main
          if (localAuthState is LocalAuthSuccess && isGoingToLockScreen) {
            debugPrint(
              "[$timestamp Redirect] Local Auth Success & on Lock Screen -> Go Main",
            );
            return AppRoutes.main;
          }

          // 8. Nếu Local Auth KHÔNG CÓ SẴN và ĐANG ở màn hình khóa -> Vào Main
          // (Shouldn't happen if LocalAuthSuccess is emitted correctly, but as a safeguard)
          if (localAuthState is LocalAuthUnavailable && isGoingToLockScreen) {
            debugPrint(
              "[$timestamp Redirect] Local Auth Unavailable & on Lock Screen -> Go Main",
            );
            return AppRoutes.main;
          }
        }

        // Các trường hợp khác (đã đăng nhập và ở trang main, chưa đăng nhập và ở trang login) -> không cần redirect
        // Các trường hợp khác không cần redirect
        debugPrint(
          "[$timestamp Redirect] No redirect needed for current states and location.",
        );
        return null;
      },
      errorBuilder:
          (context, state) => Scaffold(
            body: Center(child: Text('Page not found: ${state.error}')),
          ),
    );
  }
}
