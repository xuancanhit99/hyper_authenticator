// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/app.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/router/app_url_strategy.dart';
import 'package:hyper_authenticator/core/theme/theme_provider.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppUrlStrategy();

  try {
    await di.configureDependencies();
    final appConfig = di.sl<AppConfig>();
    await Supabase.initialize(
      url: appConfig.supabaseUrl,
      publishableKey: appConfig.supabasePublishableKey,
    );

    final sharedPreferences = di.sl<SharedPreferences>();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(sharedPreferences),
          ),
          BlocProvider<AuthBloc>.value(
            value: di.sl<AuthBloc>()..add(AuthCheckRequested()),
          ),
          BlocProvider<LocalAuthBloc>.value(
            value: di.sl<LocalAuthBloc>()..add(CheckLocalAuth()),
          ),
          BlocProvider<AccountsBloc>.value(value: di.sl<AccountsBloc>()),
          BlocProvider<SettingsBloc>(
            create: (_) => di.sl<SettingsBloc>()..add(LoadSettings()),
          ),
        ],
        child: const MyApp(),
      ),
    );
  } catch (error) {
    debugPrint('Không thể khởi tạo ứng dụng (${error.runtimeType}).');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Không thể khởi động ứng dụng. Hãy kiểm tra cấu hình Supabase.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
