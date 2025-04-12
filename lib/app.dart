// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart'; // Import GetIt instance

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Provide AuthBloc globally
    return BlocProvider<AuthBloc>(
      // Create AuthBloc instance from GetIt and trigger initial check
      create: (_) => sl<AuthBloc>()..add(AuthCheckRequested()),
      child: Builder( // Use Builder to access context with AuthBloc available
          builder: (context) {
            // Get the AppRouter instance (which now has AuthBloc) from GetIt
            final appRouter = sl<AppRouter>();
            return MaterialApp.router(
              title: 'Bill Splitter App',
              theme: sl<ThemeData>(instanceName: 'lightTheme'),
              darkTheme: sl<ThemeData>(instanceName: 'darkTheme'),
              themeMode: ThemeMode.system,
              // Use the router configuration from the instance
              routerConfig: appRouter.config(),
            );
          }
      ),
    );
  }
}