import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:hyper_authenticator/core/config/app_config.dart'; // Assuming AppConfig exists
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

@module
abstract class RegisterModule {
  // --- External Dependencies ---

  @lazySingleton
  http.Client get httpClient => http.Client();

  // Assuming Supabase is initialized in main.dart BEFORE configureDependencies is called
  @lazySingleton
  SupabaseClient get supabaseClient {
    // If Supabase might not be initialized, add a check or ensure init order in main.dart
    // assert(Supabase.instance.client != null, 'Supabase must be initialized before accessing the client');
    return Supabase.instance.client;
  }

  // AppConfig is registered automatically via @lazySingleton and @factoryMethod
  // @lazySingleton
  // AppConfig get appConfig => AppConfig.fromEnv();

  // --- Authenticator Dependencies ---

  @lazySingleton
  LocalAuthentication get localAuthentication => LocalAuthentication();

  @lazySingleton
  FlutterSecureStorage get flutterSecureStorage => const FlutterSecureStorage(
    // Optional: Configure Android/iOS options if needed
    // aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // iOptions: IOSOptions(...)
  );

  @lazySingleton
  Uuid get uuid => const Uuid();
}
