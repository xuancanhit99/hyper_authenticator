import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores the Supabase session in the same encrypted extension vault as local
/// account data. The key is namespaced so auth never collides with vault v2 or
/// sync-metadata records.
class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage(this._storage);

  static const _sessionKey = 'ha:chrome-extension:v1:supabase-session';
  final SecureKeyValueStore _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      await _storage.read(key: _sessionKey) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);
}

/// GoTrue uses this for PKCE verifier material. It is included even though the
/// MVP uses email/password, so recovery and a later OAuth flow cannot silently
/// fall back to browser localStorage.
class SecureSupabasePkceStorage extends GotrueAsyncStorage {
  SecureSupabasePkceStorage(this._storage);

  static const _prefix = 'ha:chrome-extension:v1:gotrue:';
  final SecureKeyValueStore _storage;

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: '$_prefix$key');

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: '$_prefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: '$_prefix$key', value: value);
}
