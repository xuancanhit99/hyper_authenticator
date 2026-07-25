import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'injection_container.config.dart';

final sl = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
Future<void> configureDependencies() async {
  await sl.init();
  _registerThemes();
  sl.registerLazySingleton(
    () => AppRouter(sl<AuthBloc>(), sl<LocalAuthBloc>(), sl<AppConfig>()),
  );
}

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
