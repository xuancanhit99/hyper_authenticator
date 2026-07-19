import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/services/device_key_cipher.dart';
import 'package:injectable/injectable.dart';

class DeviceKeyStoreException implements Exception {
  const DeviceKeyStoreException();

  @override
  String toString() => 'DeviceKeyStoreException(<redacted>)';
}

abstract class DeviceKeyMaterialStore {
  Future<DeviceKeyMaterial?> read({
    required String userId,
    required String installationId,
  });

  Future<DeviceKeyMaterial> getOrCreate({
    required String userId,
    required String installationId,
  });

  Future<void> delete({required String userId, required String installationId});
}

@LazySingleton(as: DeviceKeyMaterialStore)
class DeviceKeyStore implements DeviceKeyMaterialStore {
  static const _storagePrefix = 'ha:e2ee:v2:device-key:';
  static const _formatVersion = 1;
  final FlutterSecureStorage _secureStorage;
  final DeviceKeyCipher _cipher;
  final Map<String, Future<DeviceKeyMaterial>> _initializations =
      <String, Future<DeviceKeyMaterial>>{};

  DeviceKeyStore(this._secureStorage, this._cipher);

  @override
  Future<DeviceKeyMaterial?> read({
    required String userId,
    required String installationId,
  }) async {
    final storageKey = _storageKey(userId, installationId);
    try {
      final encoded = await _secureStorage.read(key: storageKey);
      if (encoded == null) return null;
      final json = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (json is! Map<String, dynamic> ||
          json['format_version'] != _formatVersion ||
          json['private_key'] is! String ||
          json['public_key'] is! String ||
          json['binding_secret'] is! String) {
        throw const DeviceKeyStoreException();
      }
      final privateKey = base64Url.decode(json['private_key'] as String);
      final publicKey = base64Url.decode(json['public_key'] as String);
      final bindingSecret = base64Url.decode(json['binding_secret'] as String);
      if (privateKey.length != 32 ||
          publicKey.length != 32 ||
          bindingSecret.length != 32) {
        throw const DeviceKeyStoreException();
      }
      final derivedPublicKey = await _cipher.publicKeyForPrivateKey(privateKey);
      if (Mac(derivedPublicKey) != Mac(publicKey)) {
        throw const DeviceKeyStoreException();
      }
      return DeviceKeyMaterial(
        privateKeyBytes: privateKey,
        publicKeyBytes: publicKey,
        bindingSecretBytes: bindingSecret,
      );
    } catch (_) {
      throw const DeviceKeyStoreException();
    }
  }

  @override
  Future<DeviceKeyMaterial> getOrCreate({
    required String userId,
    required String installationId,
  }) async {
    final storageKey = _storageKey(userId, installationId);
    final pending = _initializations[storageKey];
    if (pending != null) return pending;
    final operation = _getOrCreate(
      userId: userId,
      installationId: installationId,
      storageKey: storageKey,
    );
    _initializations[storageKey] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_initializations[storageKey], operation)) {
        _initializations.remove(storageKey);
      }
    }
  }

  @override
  Future<void> delete({
    required String userId,
    required String installationId,
  }) async {
    final storageKey = _storageKey(userId, installationId);
    try {
      await _secureStorage.delete(key: storageKey);
      if (await _secureStorage.read(key: storageKey) != null) {
        throw const DeviceKeyStoreException();
      }
    } catch (_) {
      throw const DeviceKeyStoreException();
    }
  }

  Future<DeviceKeyMaterial> _getOrCreate({
    required String userId,
    required String installationId,
    required String storageKey,
  }) async {
    final existing = await read(userId: userId, installationId: installationId);
    if (existing != null) return existing;

    final material = await _cipher.createKeyMaterial();
    final encoded = base64UrlEncode(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'format_version': _formatVersion,
          'private_key': base64UrlEncode(material.privateKeyBytes),
          'public_key': base64UrlEncode(material.publicKeyBytes),
          'binding_secret': base64UrlEncode(material.bindingSecretBytes),
        }),
      ),
    );
    try {
      if (await _secureStorage.read(key: storageKey) != null) {
        throw const DeviceKeyStoreException();
      }
      await _secureStorage.write(key: storageKey, value: encoded);
      if (await _secureStorage.read(key: storageKey) != encoded) {
        throw const DeviceKeyStoreException();
      }
      final verified = await read(
        userId: userId,
        installationId: installationId,
      );
      if (verified == null ||
          Mac(verified.privateKeyBytes) != Mac(material.privateKeyBytes) ||
          Mac(verified.publicKeyBytes) != Mac(material.publicKeyBytes) ||
          Mac(verified.bindingSecretBytes) !=
              Mac(material.bindingSecretBytes)) {
        throw const DeviceKeyStoreException();
      }
      return verified;
    } catch (_) {
      throw const DeviceKeyStoreException();
    }
  }

  String _storageKey(String userId, String installationId) {
    final userBytes = utf8.encode(userId);
    final installationBytes = utf8.encode(installationId);
    if (userId.trim().isEmpty ||
        installationId.trim().isEmpty ||
        userBytes.length > 256 ||
        installationBytes.length > 256) {
      throw const DeviceKeyStoreException();
    }
    return '$_storagePrefix${base64UrlEncode(userBytes)}.'
        '${base64UrlEncode(installationBytes)}';
  }
}
