// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/app.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/router/app_url_strategy.dart';
import 'package:hyper_authenticator/core/storage/windows_storage_migrator.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppUrlStrategy();

  try {
    await migrateWindowsStorageLayout();
    await di.configureDependencies();
    final appConfig = di.sl<AppConfig>();
    if (appConfig.cloudEnabled) {
      await Supabase.initialize(
        url: appConfig.supabaseUrl!,
        publishableKey: appConfig.supabasePublishableKey!,
      );
    }

    final sharedPreferences = di.sl<SharedPreferences>();

    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit(sharedPreferences)),
          BlocProvider<AuthBloc>.value(
            value: di.sl<AuthBloc>()..add(AuthCheckRequested()),
          ),
          BlocProvider<LocalAuthBloc>.value(
            value: di.sl<LocalAuthBloc>()..add(CheckLocalAuth()),
          ),
          BlocProvider<AccountsBloc>.value(value: di.sl<AccountsBloc>()),
        ],
        child: const MyApp(),
      ),
    );
  } on WindowsStorageMigrationConflict catch (error) {
    debugPrint('Không thể nhập kho dữ liệu Windows (${error.runtimeType}).');
    runApp(const _StartupFailureApp(message: _windowsStorageConflictMessage));
  } on WindowsStorageMigrationException catch (error) {
    debugPrint('Không thể nhập kho dữ liệu Windows (${error.runtimeType}).');
    runApp(const _StartupFailureApp(message: _windowsStorageFailureMessage));
  } catch (error) {
    debugPrint('Không thể khởi tạo ứng dụng (${error.runtimeType}).');
    runApp(const _StartupFailureApp(message: _genericStartupFailureMessage));
  }
}

const _windowsStorageConflictMessage =
    'Phát hiện xung đột khi nâng cấp kho dữ liệu Windows. Ứng dụng đã dừng để '
    'tránh ghi đè dữ liệu. Hãy sao lưu AppData và liên hệ hỗ trợ.';
const _windowsStorageFailureMessage =
    'Không thể hoàn tất nâng cấp kho dữ liệu Windows. Ứng dụng đã dừng để tránh '
    'ghi đè dữ liệu. Hãy sao lưu AppData rồi thử lại hoặc liên hệ hỗ trợ.';
const _genericStartupFailureMessage =
    'Không thể khởi động ứng dụng. Hãy kiểm tra cấu hình và thử lại.';

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
