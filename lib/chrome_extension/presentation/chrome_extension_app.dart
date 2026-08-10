import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';

/// Flutter shell for the Manifest V3 side panel.
///
/// This intentionally does not import [MyApp] or the primary router. Doing so
/// would pull mobile QR scanner code into the extension bundle before its WASM
/// decoder has a local-only packaging implementation.
class ChromeExtensionApp extends StatefulWidget {
  const ChromeExtensionApp({super.key, required this.routerConfig});

  final RouterConfig<Object> routerConfig;

  @override
  State<ChromeExtensionApp> createState() => _ChromeExtensionAppState();
}

class _ChromeExtensionAppState extends State<ChromeExtensionApp>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed && sl.isRegistered<SyncBloc>()) {
      sl<SyncBloc>().add(const SyncNowRequested());
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
      theme: AppTheme.light(themeState.style),
      darkTheme: AppTheme.dark(themeState.style),
      themeMode: themeState.mode,
      routerConfig: widget.routerConfig,
      builder: (context, child) =>
          PrivacyShield(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
    );
  }
}
