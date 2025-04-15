// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Keep Bloc for other Blocs
import 'package:provider/provider.dart'; // Import Provider
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hyper_authenticator/app.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/theme/theme_provider.dart'; // Import ThemeProvider
// Import other Blocs needed for MultiBlocProvider
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: ".env");
    await di.configureDependencies();
    final appConfig = di.sl<AppConfig>();
    await Supabase.initialize(
      url: appConfig.supabaseUrl,
      anonKey: appConfig.supabaseAnonKey,
    );

    // Get SharedPreferences instance for ThemeProvider
    final sharedPreferences = di.sl<SharedPreferences>();

    runApp(
      // Combine Bloc providers and ChangeNotifierProvider
      MultiProvider(
        providers: [
          // Provide ThemeProvider
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(sharedPreferences),
          ),
          // Provide other Blocs
          BlocProvider<AuthBloc>(
            create: (_) => di.sl<AuthBloc>()..add(AuthCheckRequested()),
          ),
          BlocProvider<LocalAuthBloc>(
            create: (_) => di.sl<LocalAuthBloc>()..add(CheckLocalAuth()),
          ),
          BlocProvider<AccountsBloc>(create: (_) => di.sl<AccountsBloc>()),
          BlocProvider<SettingsBloc>(
            create: (_) => di.sl<SettingsBloc>()..add(LoadSettings()),
          ),
        ],
        // Consumer listens to ThemeProvider to rebuild MyApp when theme changes
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            // Pass themeMode down if needed, or let MyApp consume it again
            // MyApp will now consume ThemeProvider internally
            return const MyApp();
          },
        ),
      ),
    );
  } catch (e) {
    debugPrint('Error initializing app: $e');
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text('Error initializing app: $e'))),
      ),
    );
  }
}

// Helper to access Supabase client instance easily
final supabase = Supabase.instance.client;
