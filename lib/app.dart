// lib/app.dart
import 'dart:async'; // Keep Timer import for potential future use if needed
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // Supabase Auth
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Accounts Bloc
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Local Auth Bloc
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
    super.didChangeAppLifecycleState(state);
    debugPrint("[AppLifecycle] State changed: $state");

    if (state == AppLifecycleState.resumed) {
      // App is resuming, always trigger a check
      debugPrint("[AppLifecycle] Resumed. Requesting local auth check.");
      try {
        // Check if LocalAuthBloc is available before adding event
        if (sl.isRegistered<LocalAuthBloc>()) {
          sl<LocalAuthBloc>().add(CheckLocalAuth());
        } else {
          debugPrint(
            "[AppLifecycle] LocalAuthBloc not registered yet on resume.",
          );
        }
      } catch (e) {
        debugPrint(
          "[AppLifecycle] Error accessing LocalAuthBloc on resume: $e",
        );
      }
    } else {
      // App is pausing, detaching, etc. - reset auth status
      debugPrint(
        "[AppLifecycle] Paused/Inactive/Hidden/Detached. Requesting auth status reset.",
      );
      try {
        // Check if LocalAuthBloc is available before adding event
        if (sl.isRegistered<LocalAuthBloc>()) {
          sl<LocalAuthBloc>().add(ResetAuthStatus());
        } else {
          debugPrint(
            "[AppLifecycle] LocalAuthBloc not registered yet on pause.",
          );
        }
      } catch (e) {
        debugPrint("[AppLifecycle] Error accessing LocalAuthBloc on pause: $e");
      }
    }
  }

  // _checkAndStartLockTimerIfNeeded removed as logic is simplified

  @override
  Widget build(BuildContext context) {
    // Provide all necessary Blocs globally using MultiBlocProvider
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          // Create AuthBloc instance from GetIt and trigger initial check
          create: (_) => sl<AuthBloc>()..add(AuthCheckRequested()),
        ),
        BlocProvider<LocalAuthBloc>(
          // Create LocalAuthBloc and trigger initial check
          // Initial check is important for first app launch
          create: (_) => sl<LocalAuthBloc>()..add(CheckLocalAuth()),
        ),
        BlocProvider<AccountsBloc>(
          // Create AccountsBloc (can be lazy loaded if needed, but load here for simplicity)
          // Initial LoadAccounts event will be dispatched by AccountsPage itself
          create: (_) => sl<AccountsBloc>(),
        ),
      ],
      child: Builder(
        // Use Builder to access context with Blocs available
        builder: (context) {
          // Get the AppRouter instance (which now has both Blocs injected via constructor)
          final appRouter = sl<AppRouter>();
          return MaterialApp.router(
            title: 'Hyper Authenticator', // Updated title
            theme: sl<ThemeData>(instanceName: 'lightTheme'),
            darkTheme: sl<ThemeData>(instanceName: 'darkTheme'),
            themeMode: ThemeMode.system, // Or load from settings
            // Use the router configuration from the instance
            routerConfig: appRouter.config(),
            debugShowCheckedModeBanner: false, // Optional: hide debug banner
          );
        },
      ),
    );
  }
}
