import 'package:injectable/injectable.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@module
abstract class RegisterModule {
  @lazySingleton
  SupabaseClient supabaseClient(AppConfig config) {
    if (config.cloudEnabled) return Supabase.instance.client;
    return SupabaseClient(
      'https://local-only.invalid',
      'TEST_ONLY_LOCAL_MODE_PUBLIC_KEY',
    );
  }

  @lazySingleton
  LocalAuthentication get localAuthentication => LocalAuthentication();

  @lazySingleton
  FlutterSecureStorage get flutterSecureStorage => const FlutterSecureStorage();

  @lazySingleton
  Uuid get uuid => const Uuid();

  @preResolve
  Future<SharedPreferences> get sharedPreferences =>
      SharedPreferences.getInstance();
}
