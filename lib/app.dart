// lib/app.dart
// Keep Timer import for potential future use if needed
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Keep for other Blocs if needed elsewhere
import 'package:provider/provider.dart'; // Import Provider
import 'package:hyper_authenticator/core/router/app_router.dart';
// Supabase Auth
// Accounts Bloc
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
    if (!sl.isRegistered<LocalAuthBloc>()) {
      return;
    }

    final localAuthBloc = sl<LocalAuthBloc>();
    if (state == AppLifecycleState.resumed) {
      localAuthBloc.add(CheckLocalAuth());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      localAuthBloc.add(ResetAuthStatus());
    }
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
