import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';
import 'package:hyper_authenticator/core/platform/system_ui_interaction_guard.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.routerConfig, this.lightTheme, this.darkTheme});

  final RouterConfig<Object>? routerConfig;
  final ThemeData? lightTheme;
  final ThemeData? darkTheme;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!sl.isRegistered<LocalAuthBloc>()) {
      return;
    }

    final localAuthBloc = sl<LocalAuthBloc>();
    if (state == AppLifecycleState.resumed) {
      localAuthBloc.add(CheckLocalAuth());
      if (sl.isRegistered<SyncBloc>()) {
        sl<SyncBloc>().add(const SyncNowRequested());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!SystemUiInteractionGuard.isActive) {
        localAuthBloc.add(ResetAuthStatus());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return MaterialApp.router(
      title: AppCopy.appName,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: widget.lightTheme ?? AppTheme.light(themeState.style),
      darkTheme: widget.darkTheme ?? AppTheme.dark(themeState.style),
      themeMode: themeState.mode,
      routerConfig: widget.routerConfig ?? sl<AppRouter>().config(),
      builder: (context, child) =>
          PrivacyShield(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
    );
  }
}
