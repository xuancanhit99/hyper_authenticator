// lib/core/config/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:injectable/injectable.dart';

@lazySingleton // Make sure to use @LazySingleton instead of camelCase
class AppConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;

  // Regular constructor (not private)
  AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  // Add a factory method for DI
  @factoryMethod
  static AppConfig fromEnv() {
    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty) {
      throw Exception('SUPABASE_URL not found in .env file');
    }
    if (anonKey == null || anonKey.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY not found in .env file');
    }

    return AppConfig(
      supabaseUrl: url,
      supabaseAnonKey: anonKey,
    );
  }
}
