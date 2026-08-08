import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/core/config/chrome_extension_runtime.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';

SecureKeyValueStore createSecureKeyValueStore(FlutterSecureStorage storage) {
  if (!ChromeExtensionRuntime.isEnabled) {
    return FlutterSecureKeyValueStore(storage);
  }
  return ChromeExtensionSecureKeyValueStore();
}

/// Bridge to the locally bundled `chrome_extension/vault.js` implementation.
///
/// The JavaScript side keeps a non-extractable AES-GCM key in IndexedDB via
/// structured clone and stores only authenticated ciphertext for every value.
/// This file is imported only by web builds; the factory returns it only for
/// the explicit Chrome Extension compile-time entrypoint.
class ChromeExtensionSecureKeyValueStore implements SecureKeyValueStore {
  _ExtensionVaultBridge get _bridge {
    final bridge = globalContext['hyperExtensionVault'];
    if (bridge == null) {
      throw StateError('Chrome Extension vault bridge is unavailable.');
    }
    return _ExtensionVaultBridge(bridge as JSObject);
  }

  @override
  Future<String?> read({required String key}) async {
    final value = await _bridge.read(key.toJS).toDart;
    return value?.toDart;
  }

  @override
  Future<Map<String, String>> readAll() async {
    final encoded = (await _bridge.readAllJson().toDart).toDart;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Chrome Extension vault format is invalid.');
    }
    return Map<String, String>.unmodifiable({
      for (final entry in decoded.entries)
        if (entry.value is String) entry.key: entry.value as String,
    });
  }

  @override
  Future<void> write({required String key, required String value}) async {
    await _bridge.write(key.toJS, value.toJS).toDart;
  }

  @override
  Future<void> delete({required String key}) async {
    await _bridge.delete(key.toJS).toDart;
  }
}

extension type _ExtensionVaultBridge(JSObject _) implements JSObject {
  external JSPromise<JSString?> read(JSString key);
  external JSPromise<JSString> readAllJson();
  external JSPromise<JSAny?> write(JSString key, JSString value);
  external JSPromise<JSAny?> delete(JSString key);
}
