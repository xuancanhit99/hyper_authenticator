// lib/core/router/app_router.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // Import AuthBloc
import 'package:hyper_authenticator/features/auth/presentation/pages/auth_page.dart';

import 'package:hyper_authenticator/features/auth/presentation/pages/home_page.dart';// Import ChatbotPage
import 'package:flutter_bloc/flutter_bloc.dart'; // Import BlocProvider// Import the Bloc
import 'package:hyper_authenticator/injection_container.dart'; // Import sl
// Removed import for reset_password_page.dart

// --- Define Route Paths ---
class AppRoutes {
  static const splash = '/splash'; // Optional loading screen
  static const login = '/login';
  static const signup = '/signup'; // Added signup path
  static const home = '/';
}

class AppRouter {
  final AuthBloc authBloc; // Receive AuthBloc instance

  AppRouter(this.authBloc); // Constructor

  static String get loginPath => AppRoutes.login;
  static String get signupPath => AppRoutes.signup;

  GoRouter config() {
    return GoRouter(
      // Start at home, redirect logic will handle auth state
      initialLocation: AppRoutes.home,
      // Refresh stream listens to AuthBloc state changes for automatic redirection
      refreshListenable: GoRouterRefreshStream(authBloc.stream),
      routes: [
        // Public routes
        GoRoute(
          path: AppRoutes.login,
          name: AppRoutes.login, // Optional: Use names for navigation
          // Use builder for LoginPage as it doesn't need BillSplittingBloc directly
          builder: (context, state) => const LoginPage(),
        ),
        // GoRoute(
        //   path: AppRoutes.signup,
        //   name: AppRoutes.signup,
        //   builder: (context, state) => const SignUpPage(),
        // ),
        // Authenticated routes (add more here)
        GoRoute(
          path: AppRoutes.home,
          name: AppRoutes.home,
          builder: (context, state) => const HomePage(),
        ),
      ],

      // --- REDIRECT LOGIC ---
      redirect: (BuildContext context, GoRouterState state) {
        final currentState = authBloc.state; // Get current Bloc state
        final loggingIn = state.matchedLocation == AppRoutes.login;
        final signingUp = state.matchedLocation == AppRoutes.signup;
        // Removed resettingPassword check
        final isPublicRoute =
            loggingIn || signingUp; // Only login and signup are public now

        // Don't redirect during initial check or if already on a public route when unauthenticated
        if (currentState is AuthInitial || currentState is AuthLoading) {
          return null; // Stay put while checking
        }

        final isAuthenticated = currentState is AuthAuthenticated;

        // If authenticated and trying to access login/signup, redirect to home
        if (isAuthenticated && isPublicRoute) {
          debugPrint(
              "Redirecting authenticated user from public route to home");
          return AppRoutes.home;
        }

        // If unauthenticated and trying to access a protected route, redirect to login


        // No redirect needed
        return null;
      },
      errorBuilder: (context, state) => Scaffold(
        // Basic error page
        body: Center(child: Text('Page not found: ${state.error}')),
      ),
    );
  }
}

// Helper class to trigger GoRouter refresh on Bloc stream changes
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
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
