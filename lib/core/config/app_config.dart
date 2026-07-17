// lib/core/config/app_config.dart
import 'package:injectable/injectable.dart';

@lazySingleton
class AppConfig {
  final String supabaseUrl;
  final String supabasePublishableKey;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  @factoryMethod
  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );

    if (url.isEmpty) {
      throw StateError('Thiếu cấu hình SUPABASE_URL');
    }
    if (publishableKey.isEmpty) {
      throw StateError('Thiếu cấu hình SUPABASE_PUBLISHABLE_KEY');
    }

    return const AppConfig(
      supabaseUrl: url,
      supabasePublishableKey: publishableKey,
    );
  }
}
