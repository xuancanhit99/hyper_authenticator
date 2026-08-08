import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';

SecureKeyValueStore createSecureKeyValueStore(FlutterSecureStorage storage) =>
    FlutterSecureKeyValueStore(storage);
