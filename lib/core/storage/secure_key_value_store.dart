import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';

abstract interface class ExclusiveSecureKeyValueStore {
  Future<T> runExclusive<T>(Future<T> Function() operation);
}

Future<void> _storageTail = Future<void>.value();

/// Shared by datasource instances. Browser extensions additionally coordinate
/// through Web Locks across Dart isolates/pages; no network is held inside it.
Future<T> runStorageExclusive<T>(
  SecureKeyValueStore storage,
  Future<T> Function() operation,
) {
  final result = Completer<T>();
  _storageTail = _storageTail.then((_) async {
    try {
      result.complete(
        await (storage is ExclusiveSecureKeyValueStore
            ? (storage as ExclusiveSecureKeyValueStore).runExclusive(operation)
            : operation()),
      );
    } catch (error, stack) {
      result.completeError(error, stack);
    }
  });
  return result.future;
}

/// Small, platform-neutral boundary for credential-bearing local records.
///
/// Feature data sources depend on this contract rather than a plugin so the
/// Chrome Extension can use its dedicated IndexedDB/WebCrypto vault without
/// changing the shared local-vault serialization contract.
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
