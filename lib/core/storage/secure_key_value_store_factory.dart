import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';

import 'secure_key_value_store_factory_stub.dart'
    if (dart.library.js_interop) 'secure_key_value_store_factory_web.dart'
    as implementation;

SecureKeyValueStore createSecureKeyValueStore(FlutterSecureStorage storage) =>
    implementation.createSecureKeyValueStore(storage);
