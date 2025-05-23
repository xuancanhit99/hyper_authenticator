import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Import LocalAuthBloc
import 'injection_container.config.dart'; // Import the generated config file

final sl = GetIt.instance;

@InjectableInit(
  initializerName: 'init', // default
  preferRelativeImports: true, // default
  asExtension: true, // Thay đổi thành true
)
Future<void> configureDependencies() async {
  // Use the generated extension method 'init'
  await sl.init();

  // External dependencies are now handled by RegisterModule

  // Register manual dependencies that might not work with @injectable
  _registerThemes();

  // Register AppRouter manually after its dependencies (Blocs) are registered by injectable
  // Ensure AuthBloc is registered by injectable (e.g., add @injectable to AuthBloc class)
  // For now, assuming AuthBloc is registered.
  sl.registerLazySingleton(
    () => AppRouter(sl<AuthBloc>(), sl<LocalAuthBloc>()), // Pass both Blocs
  );
}

// Removed _registerExternalDependencies function as it's handled by @module

void _registerThemes() {
  sl.registerLazySingleton<ThemeData>(
    () => AppTheme.lightTheme,
    instanceName: 'lightTheme',
  );
  sl.registerLazySingleton<ThemeData>(
    () => AppTheme.darkTheme,
    instanceName: 'darkTheme',
  );
}
