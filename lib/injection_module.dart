import 'package:injectable/injectable.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store_factory.dart';
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
  SecureKeyValueStore secureKeyValueStore(FlutterSecureStorage storage) =>
      createSecureKeyValueStore(storage);

  @lazySingleton
  Uuid get uuid => const Uuid();

  @preResolve
  Future<SharedPreferences> get sharedPreferences =>
      SharedPreferences.getInstance();
}
