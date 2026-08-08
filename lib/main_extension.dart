import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/chrome_extension/data/secure_supabase_storage.dart';
import 'package:hyper_authenticator/chrome_extension/presentation/chrome_extension_app.dart';
import 'package:hyper_authenticator/chrome_extension/presentation/chrome_extension_router.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manifest V3 entrypoint. Build only with
/// `--dart-define=HYPER_CHROME_EXTENSION=true` via the extension harness.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await di.configureDependencies();
    final appConfig = di.sl<AppConfig>();
    if (appConfig.cloudEnabled) {
      final secureStorage = di.sl<SecureKeyValueStore>();
      await Supabase.initialize(
        url: appConfig.supabaseUrl!,
        publishableKey: appConfig.supabasePublishableKey!,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSupabaseLocalStorage(secureStorage),
          pkceAsyncStorage: SecureSupabasePkceStorage(secureStorage),
        ),
      );
    }

    final sharedPreferences = di.sl<SharedPreferences>();
    final authBloc = di.sl<AuthBloc>()..add(AuthCheckRequested());
    final router = ChromeExtensionRouter(authBloc, appConfig);

    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit(sharedPreferences)),
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<AccountsBloc>.value(value: di.sl<AccountsBloc>()),
          BlocProvider<SyncBloc>.value(value: di.sl<SyncBloc>()),
        ],
        child: ChromeExtensionApp(routerConfig: router.config()),
      ),
    );
  } catch (error) {
    debugPrint('Không thể khởi tạo Chrome Extension (${error.runtimeType}).');
    runApp(const _ExtensionStartupFailureApp());
  }
}

class _ExtensionStartupFailureApp extends StatelessWidget {
  const _ExtensionStartupFailureApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Không thể khởi động extension. Hãy mở lại Side Panel hoặc kiểm '
            'tra cấu hình phát hành.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
