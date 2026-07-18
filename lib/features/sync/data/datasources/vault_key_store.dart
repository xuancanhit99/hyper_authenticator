import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:hyper_authenticator/features/sync/domain/services/vault_cipher.dart';
import 'package:injectable/injectable.dart';

class VaultKeyStoreException implements Exception {
  const VaultKeyStoreException();
}

@lazySingleton
class VaultKeyStore {
  static const _keyPrefix = 'ha:e2ee:v1:dek:';
  final FlutterSecureStorage _secureStorage;
  final VaultCipher _cipher;

  VaultKeyStore(this._secureStorage, this._cipher);

  Future<List<int>?> readDataKey(String userId) async {
    _requireUserId(userId);
    try {
      final encoded = await _secureStorage.read(key: '$_keyPrefix$userId');
      if (encoded == null) {
        return null;
      }
      final bytes = base64Url.decode(encoded);
      if (bytes.length != 32) {
        throw const VaultKeyStoreException();
      }
      return List<int>.unmodifiable(bytes);
    } catch (_) {
      throw const VaultKeyStoreException();
    }
  }

  Future<VaultKeyBundle> initializeForUser(String userId) async {
    _requireUserId(userId);
    if (await readDataKey(userId) != null) {
      throw const VaultKeyStoreException();
    }
    final bundle = await _cipher.createKeyBundle(userId: userId);
    await _writeVerified(userId, bundle.dataKeyBytes);
    return bundle;
  }

  Future<void> writeDataKey(String userId, List<int> dataKeyBytes) async {
    _requireUserId(userId);
    if (dataKeyBytes.length != 32) {
      throw const VaultKeyStoreException();
    }
    await _writeVerified(userId, dataKeyBytes);
  }

  Future<void> deleteDataKey(String userId) async {
    _requireUserId(userId);
    try {
      await _secureStorage.delete(key: '$_keyPrefix$userId');
      if (await _secureStorage.read(key: '$_keyPrefix$userId') != null) {
        throw const VaultKeyStoreException();
      }
    } catch (_) {
      throw const VaultKeyStoreException();
    }
  }

  Future<List<int>> recoverForUser({
    required String userId,
    required String recoveryCode,
    required WrappedVaultKey wrappedKey,
  }) async {
    _requireUserId(userId);
    final dataKey = await _cipher.unwrapDataKey(
      wrappedKey: wrappedKey,
      recoveryCode: recoveryCode,
      userId: userId,
    );
    await _writeVerified(userId, dataKey);
    return dataKey;
  }

  Future<void> _writeVerified(String userId, List<int> bytes) async {
    try {
      final encoded = base64UrlEncode(bytes);
      final key = '$_keyPrefix$userId';
      await _secureStorage.write(key: key, value: encoded);
      if (await _secureStorage.read(key: key) != encoded) {
        throw const VaultKeyStoreException();
      }
    } catch (_) {
      throw const VaultKeyStoreException();
    }
  }

  void _requireUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw const VaultKeyStoreException();
    }
  }
}
