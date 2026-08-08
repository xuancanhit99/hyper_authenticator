import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small, platform-neutral boundary for credential-bearing local records.
///
/// Feature data sources depend on this contract rather than a plugin so the
/// Chrome Extension can use its dedicated IndexedDB/WebCrypto vault without
/// changing the local-vault v2 or sync-metadata formats.
abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});

  Future<Map<String, String>> readAll();

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
