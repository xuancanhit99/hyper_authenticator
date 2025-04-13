// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
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

// Helper class to trigger GoRouter refresh on Bloc stream changes (Giữ nguyên từ bản gốc)
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners(); // Notify initially to trigger first redirect check
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  final AuthBloc authBloc; // Chỉ cần AuthBloc cho redirect này
  // final LocalAuthBloc localAuthBloc; // Tạm thời không dùng trong redirect

  AppRouter(this.authBloc); // Chỉ cần AuthBloc

  static String get loginPath => AppRoutes.login;

  GoRouter config() {
    return GoRouter(
      initialLocation: AppRoutes.main, // Bắt đầu ở trang chính
      // Chỉ lắng nghe AuthBloc để refresh redirect
      refreshListenable: GoRouterRefreshStream(authBloc.stream),
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
        final location = state.matchedLocation;
        final isGoingToLogin = location == AppRoutes.login;

        debugPrint(
          "[Redirect Simple] State: ${supabaseAuthState.runtimeType}, Location: $location",
        );

        // 1. Chờ Supabase Auth load xong
        if (supabaseAuthState is AuthInitial ||
            supabaseAuthState is AuthLoading) {
          debugPrint("[Redirect Simple] Waiting for Supabase Auth...");
          return null; // Chờ
        }

        final isSupabaseAuthenticated = supabaseAuthState is AuthAuthenticated;

        // 2. Nếu CHƯA đăng nhập Supabase và KHÔNG ở trang Login -> Về Login
        if (!isSupabaseAuthenticated && !isGoingToLogin) {
          debugPrint(
            "[Redirect Simple] Unauthenticated & not on Login -> Go Login",
          );
          return AppRoutes.login;
        }

        // 3. Nếu ĐÃ đăng nhập Supabase và ĐANG ở trang Login -> Vào Main
        if (isSupabaseAuthenticated && isGoingToLogin) {
          debugPrint("[Redirect Simple] Authenticated & on Login -> Go Main");
          return AppRoutes.main;
        }

        // Các trường hợp khác (đã đăng nhập và ở trang main, chưa đăng nhập và ở trang login) -> không cần redirect
        debugPrint("[Redirect Simple] No redirect needed.");
        return null;
      },
      errorBuilder:
          (context, state) => Scaffold(
            body: Center(child: Text('Page not found: ${state.error}')),
          ),
    );
  }
}
