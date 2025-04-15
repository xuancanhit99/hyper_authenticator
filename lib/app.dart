// lib/app.dart
import 'dart:async'; // Keep Timer import for potential future use if needed
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Keep for other Blocs if needed elsewhere
import 'package:provider/provider.dart'; // Import Provider
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // Supabase Auth
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Accounts Bloc
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Local Auth Bloc
// SettingsBloc import no longer needed here
import 'package:hyper_authenticator/core/theme/theme_provider.dart'; // Import ThemeProvider
import 'package:hyper_authenticator/injection_container.dart'; // Import GetIt instance
// SharedPreferences no longer needed directly here
// import 'package:shared_preferences/shared_preferences.dart';

// Key must match the one used in SettingsBloc and LocalAuthBloc
// const String _biometricPrefKey = 'biometric_enabled'; // No longer needed here

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AppLifecycleState? _previousLifecycleState; // Store the previous state

  // Timer? _resumeLockTimer; // Timer logic removed
  // StreamSubscription? _authSubscription; // Auth listener removed, handled by router/bloc
  // bool _isResumed = false; // No longer needed

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No need to listen to AuthBloc here anymore
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // _resumeLockTimer?.cancel(); // Timer removed
    // _authSubscription?.cancel(); // Listener removed
    super.dispose();
  }

  // Auth state changes are handled by the router's redirect logic

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // It's generally better practice to update the state variable *after* using the previous value
    final previousState = _previousLifecycleState;
    super.didChangeAppLifecycleState(state); // Call super early
    debugPrint(
      "[AppLifecycle] State changed: $state (Previous: $previousState)",
    );

    try {
      // Check if LocalAuthBloc is available before adding events
      if (sl.isRegistered<LocalAuthBloc>()) {
        final localAuthBloc = sl<LocalAuthBloc>();

        if (state == AppLifecycleState.resumed) {
          // Always request a check when resuming.
          // LocalAuthBloc internally handles whether to show prompt based on its current state
          // (e.g., it won't prompt if already in LocalAuthSuccess and not reset).
          debugPrint("[AppLifecycle] Resumed. Requesting local auth check.");
          localAuthBloc.add(CheckLocalAuth());
        } else if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) {
          // Reset auth status only when pausing or detaching.
          // This prevents reset on inactive/hidden states.
          debugPrint(
            "[AppLifecycle] State is $state. Requesting auth status reset.",
          );
          localAuthBloc.add(ResetAuthStatus());
        }
        // No action needed for inactive or hidden states regarding LocalAuthBloc.
      } else {
        debugPrint(
          "[AppLifecycle] LocalAuthBloc not registered yet during state change to $state.",
        );
      }
    } catch (e) {
      debugPrint(
        "[AppLifecycle] Error accessing LocalAuthBloc during state change to $state: $e",
      );
    }

    // Store the current state for the next change detection
    _previousLifecycleState = state;
  }

  // _checkAndStartLockTimerIfNeeded removed as logic is simplified

  @override
  Widget build(BuildContext context) {
    // Blocs are provided in main.dart
    // Get ThemeProvider using context.watch to rebuild when theme changes
    final themeProvider = context.watch<ThemeProvider>();
    final appRouter = sl<AppRouter>();

    return MaterialApp.router(
      // No ValueKey needed here as Consumer in main.dart handles rebuild
      title: 'Hyper Authenticator',
      theme: sl<ThemeData>(instanceName: 'lightTheme'),
      darkTheme: sl<ThemeData>(instanceName: 'darkTheme'),
      themeMode: themeProvider.themeMode, // Use themeMode from ThemeProvider
      routerConfig: appRouter.config(),
      debugShowCheckedModeBanner: false,
    );
  }
}
