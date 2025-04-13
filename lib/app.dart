// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter/material.dart'; // Keep existing imports
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // Supabase Auth
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Accounts Bloc
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Local Auth Bloc
import 'package:hyper_authenticator/injection_container.dart'; // Import GetIt instance

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
