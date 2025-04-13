// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/pages/auth_page.dart'; // LoginPage
// import 'package:hyper_authenticator/features/auth/presentation/pages/home_page.dart'; // No longer used directly here
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Import LocalAuthBloc
import 'package:hyper_authenticator/features/authenticator/presentation/pages/accounts_page.dart'; // Import AccountsPage
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart'; // Import AddAccountPage
import 'package:hyper_authenticator/features/authenticator/presentation/pages/lock_screen_page.dart'; // Import LockScreenPage (will create)
import 'package:hyper_authenticator/injection_container.dart'; // Import sl

// --- Define Route Paths ---
class AppRoutes {
  // static const splash = '/splash'; // Optional loading screen
  static const login = '/login';
  // static const signup = '/signup'; // Assuming signup is part of LoginPage or separate flow
  static const accounts = '/accounts'; // Main screen for authenticator accounts
  static const addAccount = '/add-account';
  static const lockScreen = '/lock-screen'; // Screen to prompt local auth
}

class AppRouter {
  final AuthBloc authBloc;
  final LocalAuthBloc localAuthBloc; // Inject LocalAuthBloc

  AppRouter(this.authBloc, this.localAuthBloc); // Updated Constructor

  static String get loginPath => AppRoutes.login;
  // static String get signupPath => AppRoutes.signup; // Removed if not used

  GoRouter config() {
    return GoRouter(
      // Start at accounts page, redirect logic handles auth/lock state
      initialLocation: AppRoutes.accounts,
      // Refresh stream listens to both AuthBloc and LocalAuthBloc state changes
      refreshListenable: MultiStreamListenable([
        authBloc.stream,
        localAuthBloc.stream,
      ]),
      routes: [
        // Public routes
        GoRoute(
          path: AppRoutes.login,
          name: AppRoutes.login, // Optional: Use names for navigation
          // Use builder for LoginPage as it doesn't need BillSplittingBloc directly
          builder: (context, state) => const LoginPage(),
        ),
        // Lock Screen Route (publicly accessible technically, but redirect handles logic)
        GoRoute(
          path: AppRoutes.lockScreen,
          name: AppRoutes.lockScreen,
          builder:
              (context, state) =>
                  const LockScreenPage(), // Will create this page
        ),
        // Authenticated routes (require Supabase auth AND local auth unlock)
        GoRoute(
          path: AppRoutes.accounts,
          name: AppRoutes.accounts,
          builder: (context, state) => const AccountsPage(),
          routes: [
            // Nested route for adding account
            GoRoute(
              path: 'add', // Relative path -> /accounts/add
              name:
                  AppRoutes
                      .addAccount, // Use a distinct name if needed elsewhere
              builder: (context, state) => const AddAccountPage(),
            ),
          ],
        ),
        // AddAccount route (can also be top-level if preferred)
        // GoRoute(
        //   path: AppRoutes.addAccount,
        //   name: AppRoutes.addAccount,
        //   builder: (context, state) => const AddAccountPage(),
        // ),
      ],

      // --- REDIRECT LOGIC ---
      redirect: (BuildContext context, GoRouterState state) {
        final supabaseAuthState = authBloc.state;
        final localAuthState = localAuthBloc.state;

        final isSupabaseAuthLoading =
            supabaseAuthState is AuthInitial ||
            supabaseAuthState is AuthLoading;
        final isLocalAuthLoading =
            localAuthState is LocalAuthInitial; // Check local auth status

        // If either is still loading, don't redirect yet
        if (isSupabaseAuthLoading || isLocalAuthLoading) {
          debugPrint("Redirect: Waiting for auth states to load...");
          return null;
        }

        final isSupabaseAuthenticated = supabaseAuthState is AuthAuthenticated;
        final isAppUnlocked =
            localAuthState is LocalAuthSuccess ||
            localAuthState
                is LocalAuthUnavailable; // Unlocked or no lock needed

        final location = state.matchedLocation;
        final isGoingToLogin = location == AppRoutes.login;
        final isGoingToLockScreen = location == AppRoutes.lockScreen;
        final isGoingToPublic =
            isGoingToLogin ||
            isGoingToLockScreen; // Routes accessible before full auth/unlock

        debugPrint(
          "Redirect Check: SupabaseAuth=$isSupabaseAuthenticated, AppUnlocked=$isAppUnlocked, Location=$location",
        );

        // --- Local Auth Check (Priority 1) ---
        // If local auth is required but not passed, and we are NOT already going to the lock screen
        if (localAuthState is LocalAuthRequired && !isGoingToLockScreen) {
          debugPrint(
            "Redirect: Local auth required, redirecting to Lock Screen.",
          );
          return AppRoutes.lockScreen;
        }
        // If local auth passed, but we are still on the lock screen, redirect to accounts
        if (isAppUnlocked && isGoingToLockScreen) {
          debugPrint(
            "Redirect: App unlocked, leaving Lock Screen for Accounts.",
          );
          return AppRoutes.accounts;
        }

        // --- Supabase Auth Check (Priority 2 - only if app is unlocked or lock not needed) ---
        if (isAppUnlocked) {
          // If Supabase authenticated and trying to access login, redirect to accounts
          if (isSupabaseAuthenticated && isGoingToLogin) {
            debugPrint(
              "Redirect: Supabase authenticated, redirecting from Login to Accounts.",
            );
            return AppRoutes.accounts;
          }

          // If Supabase NOT authenticated and trying to access a protected route (not login/lock)
          if (!isSupabaseAuthenticated && !isGoingToPublic) {
            debugPrint(
              "Redirect: Supabase unauthenticated, redirecting to Login.",
            );
            return AppRoutes.login;
          }
        } else if (!isGoingToLockScreen) {
          // This case handles if local auth is somehow required but the state isn't LocalAuthRequired yet (should be rare)
          // Or if the initial check hasn't run. Redirect to lock screen as a safeguard.
          debugPrint(
            "Redirect: App not unlocked state, redirecting to Lock Screen (safeguard).",
          );
          return AppRoutes.lockScreen;
        }

        // No redirect needed in all other cases
        debugPrint("Redirect: No redirect needed.");
        return null;
      },
      errorBuilder:
          (context, state) => Scaffold(
            // Basic error page
            body: Center(child: Text('Page not found: ${state.error}')),
          ),
    );
  }
}

// Helper class to trigger GoRouter refresh on Bloc stream changes
// Helper class to trigger GoRouter refresh on MULTIPLE Bloc stream changes
class MultiStreamListenable extends ChangeNotifier {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  MultiStreamListenable(List<Stream<dynamic>> streams) {
    // Don't notify initially, let the redirect logic handle the first pass
    // notifyListeners();
    for (final stream in streams) {
      _subscriptions.add(
        stream.asBroadcastStream().listen((dynamic _) => notifyListeners()),
      );
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
