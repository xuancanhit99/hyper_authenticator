import 'dart:convert';

import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Native session/PKCE persistence. A verified secure envelope (including a
/// removal tombstone) is authoritative over interrupted legacy migrations.
class NativeAuthValues {
  NativeAuthValues(this.storage, this.preferences, String supabaseUrl)
    : legacySessionKey =
          'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
      namespace = 'ha:native-auth:v1:${Uri.parse(supabaseUrl).origin}:';

  static const pkceKey = 'supabase.auth.token-code-verifier';
  final SecureKeyValueStore storage;
  final SharedPreferences preferences;
  final String legacySessionKey;
  final String namespace;

  Future<void> initialize() async {
    await read(legacySessionKey);
    await read(pkceKey);
  }

  Future<String?> read(String key) =>
      runStorageExclusive(storage, () => _read(key));

  Future<String?> _read(String key) async {
    var encoded = await storage.read(key: '$namespace$key');
    if (encoded == null) {
      final legacy = preferences.getString(key);
      if (legacy == null) return null;
      await _write(key, legacy);
      encoded = await storage.read(key: '$namespace$key');
    }
    final envelope = jsonDecode(encoded!);
    if (envelope is! Map<String, dynamic> ||
        envelope['version'] != 1 ||
        !envelope.containsKey('value') ||
        (envelope['value'] != null && envelope['value'] is! String)) {
      throw const FormatException('Secure auth storage is unavailable.');
    }
    await _removeLegacy(key);
    return envelope['value'] as String?;
  }

  Future<void> write(String key, String? value) =>
      runStorageExclusive(storage, () => _write(key, value));

  Future<void> _write(String key, String? value) async {
    final encoded = jsonEncode({'version': 1, 'value': value});
    await storage.write(key: '$namespace$key', value: encoded);
    if (await storage.read(key: '$namespace$key') != encoded) {
      throw const FormatException('Secure auth verification failed.');
    }
    await _removeLegacy(key);
  }

  Future<void> _removeLegacy(String key) async {
    if (preferences.containsKey(key)) {
      if (!await preferences.remove(key) || preferences.containsKey(key)) {
        throw const FormatException('Legacy auth cleanup failed.');
      }
    }
  }
}

class NativeSupabaseLocalStorage extends LocalStorage {
  NativeSupabaseLocalStorage(this.values);
  final NativeAuthValues values;
  @override
  Future<void> initialize() => values.initialize();
  @override
  Future<String?> accessToken() => values.read(values.legacySessionKey);
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) =>
      values.write(values.legacySessionKey, persistSessionString);
  @override
  Future<void> removePersistedSession() =>
      values.write(values.legacySessionKey, null);
}

class NativeSupabasePkceStorage extends GotrueAsyncStorage {
  NativeSupabasePkceStorage(this.values);
  final NativeAuthValues values;
  @override
  Future<String?> getItem({required String key}) => values.read(key);
  @override
  Future<void> setItem({required String key, required String value}) =>
      values.write(key, value);
  @override
  Future<void> removeItem({required String key}) => values.write(key, null);
}
