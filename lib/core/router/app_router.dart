// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Import LocalAuthBloc
import 'package:hyper_authenticator/features/auth/presentation/pages/auth_page.dart'; // LoginPage
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/lock_screen_page.dart'; // Keep for potential future use? Or remove if not handled by router
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/injection_container.dart'; // Import sl (nếu cần) - Hiện tại không cần trực tiếp

// --- Define Route Paths ---
class AppRoutes {
  static const login = '/login';
  static const main = '/'; // Main screen (wrapper with bottom nav)
  static const addAccount = '/add-account';
  static const lockScreen = '/lock-screen'; // Bỏ comment để sử dụng
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
          name: AppRoutes.login,
          builder: (context, state) => const LoginPage(),
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
      ],

      // --- REDIRECT LOGIC (Simplified, based on original working version) ---
      redirect: (BuildContext context, GoRouterState state) {
        final supabaseAuthState = authBloc.state;
        final localAuthState = localAuthBloc.state;
        final location = state.matchedLocation;

        final isGoingToLogin = location == AppRoutes.login;
        final isGoingToLockScreen = location == AppRoutes.lockScreen;

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
        if (!isSupabaseAuthenticated && !isGoingToLogin) {
          debugPrint(
            "[$timestamp Redirect] Unauthenticated & not on Login -> Go Login",
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
