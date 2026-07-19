import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/services/hpke_base_cipher.dart';

class DeviceKeyCryptoException implements Exception {
  final String message;

  const DeviceKeyCryptoException(this.message);

  @override
  String toString() => 'DeviceKeyCryptoException: $message';
}

class DeviceKeyCipher {
  static const _keyLength = 32;
  final X25519 _keyExchange;
  final HpkeBaseCipher _hpke;
  final Hkdf _membershipKdf;
  final Hmac _membershipMac;
  final AesGcm _randomKeySource;

  DeviceKeyCipher()
    : _keyExchange = X25519(),
      _hpke = HpkeBaseCipher(),
      _membershipKdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength),
      _membershipMac = Hmac.sha256(),
      _randomKeySource = AesGcm.with256bits();

  Future<DeviceKeyMaterial> createKeyMaterial() async {
    try {
      final keyPair = await _keyExchange.newKeyPair();
      final keyPairData = await keyPair.extract();
      final publicKey = await keyPair.extractPublicKey();
      final bindingSecret = await (await _randomKeySource.newSecretKey())
          .extractBytes();
      return DeviceKeyMaterial(
        privateKeyBytes: keyPairData.bytes,
        publicKeyBytes: publicKey.bytes,
        bindingSecretBytes: bindingSecret,
      );
    } catch (_) {
      throw const DeviceKeyCryptoException(
        'Không thể tạo device key material.',
      );
    }
  }

  Future<List<int>> publicKeyForPrivateKey(List<int> privateKeyBytes) async {
    _requireKey(privateKeyBytes, 'Device private key');
    try {
      final keyPair = await _keyExchange.newKeyPairFromSeed(privateKeyBytes);
      return List<int>.unmodifiable((await keyPair.extractPublicKey()).bytes);
    } catch (_) {
      throw const DeviceKeyCryptoException('Device private key không hợp lệ.');
    }
  }

  Future<DeviceWrappedVaultKey> wrapDataKey({
    required List<int> dataKeyBytes,
    required List<int> recipientPublicKeyBytes,
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
  }) async {
    _validateContext(
      dataKeyBytes: dataKeyBytes,
      publicKeyBytes: recipientPublicKeyBytes,
      userId: userId,
      installationId: installationId,
      deviceKeyId: deviceKeyId,
      keyGeneration: keyGeneration,
    );
    try {
      final sealed = await _hpke.seal(
        recipientPublicKey: recipientPublicKeyBytes,
        plaintext: dataKeyBytes,
        info: _hpkeInfo(
          userId: userId,
          installationId: installationId,
          deviceKeyId: deviceKeyId,
          keyGeneration: keyGeneration,
        ),
        aad: _hpkeAad(
          userId: userId,
          installationId: installationId,
          deviceKeyId: deviceKeyId,
          keyGeneration: keyGeneration,
          publicKeyBytes: recipientPublicKeyBytes,
        ),
      );
      return DeviceWrappedVaultKey(
        formatVersion: DeviceWrappedVaultKey.currentFormatVersion,
        keyGeneration: keyGeneration,
        kem: DeviceWrappedVaultKey.kemName,
        kdf: DeviceWrappedVaultKey.kdfName,
        aead: DeviceWrappedVaultKey.aeadName,
        encapsulatedKey: base64UrlEncode(sealed.encapsulatedKey),
        ciphertext: base64UrlEncode(sealed.ciphertext),
        authTag: base64UrlEncode(sealed.authTag),
      );
    } on HpkeException catch (error) {
      throw DeviceKeyCryptoException(error.message);
    } on DeviceKeyCryptoException {
      rethrow;
    } catch (_) {
      throw const DeviceKeyCryptoException(
        'Không thể wrap vault key cho thiết bị.',
      );
    }
  }

  Future<List<int>> unwrapDataKey({
    required DeviceWrappedVaultKey wrappedKey,
    required List<int> recipientPrivateKeyBytes,
    required List<int> recipientPublicKeyBytes,
    required String userId,
    required String installationId,
    required String deviceKeyId,
  }) async {
    _validateContext(
      dataKeyBytes: List<int>.filled(_keyLength, 0),
      publicKeyBytes: recipientPublicKeyBytes,
      userId: userId,
      installationId: installationId,
      deviceKeyId: deviceKeyId,
      keyGeneration: wrappedKey.keyGeneration,
    );
    _requireKey(recipientPrivateKeyBytes, 'Device private key');
    _validateEnvelope(wrappedKey);
    try {
      final derivedPublicKey = await publicKeyForPrivateKey(
        recipientPrivateKeyBytes,
      );
      if (Mac(derivedPublicKey) != Mac(recipientPublicKeyBytes)) {
        throw const DeviceKeyCryptoException(
          'Device private/public key không khớp.',
        );
      }
      final clearText = await _hpke.open(
        recipientPrivateKey: recipientPrivateKeyBytes,
        sealed: HpkeCiphertext(
          encapsulatedKey: _decode(wrappedKey.encapsulatedKey),
          ciphertext: _decode(wrappedKey.ciphertext),
          authTag: _decode(wrappedKey.authTag),
        ),
        info: _hpkeInfo(
          userId: userId,
          installationId: installationId,
          deviceKeyId: deviceKeyId,
          keyGeneration: wrappedKey.keyGeneration,
        ),
        aad: _hpkeAad(
          userId: userId,
          installationId: installationId,
          deviceKeyId: deviceKeyId,
          keyGeneration: wrappedKey.keyGeneration,
          publicKeyBytes: recipientPublicKeyBytes,
        ),
      );
      _requireKey(clearText, 'Vault data key');
      return List<int>.unmodifiable(clearText);
    } on HpkeException catch (error) {
      throw DeviceKeyCryptoException(error.message);
    } on DeviceKeyCryptoException {
      rethrow;
    } catch (_) {
      throw const DeviceKeyCryptoException(
        'Không thể unwrap vault key của thiết bị.',
      );
    }
  }

  Future<String> createMembershipProof({
    required List<int> dataKeyBytes,
    required List<int> publicKeyBytes,
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
  }) async {
    _validateContext(
      dataKeyBytes: dataKeyBytes,
      publicKeyBytes: publicKeyBytes,
      userId: userId,
      installationId: installationId,
      deviceKeyId: deviceKeyId,
      keyGeneration: keyGeneration,
    );
    final context = _membershipContext(
      userId: userId,
      installationId: installationId,
      deviceKeyId: deviceKeyId,
      keyGeneration: keyGeneration,
      publicKeyBytes: publicKeyBytes,
    );
    final proofKey = await _membershipKdf.deriveKey(
      secretKey: SecretKey(dataKeyBytes),
      nonce: utf8.encode(
        'hyper-authenticator:v1:device-membership-kdf:$userId:$keyGeneration',
      ),
      info: context,
    );
    final proof = await _membershipMac.calculateMac(
      context,
      secretKey: proofKey,
    );
    return base64UrlEncode(proof.bytes);
  }

  Future<bool> verifyMembershipProof({
    required String proof,
    required List<int> dataKeyBytes,
    required List<int> publicKeyBytes,
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
  }) async {
    try {
      final expected = await createMembershipProof(
        dataKeyBytes: dataKeyBytes,
        publicKeyBytes: publicKeyBytes,
        userId: userId,
        installationId: installationId,
        deviceKeyId: deviceKeyId,
        keyGeneration: keyGeneration,
      );
      return Mac(_decode(expected)) == Mac(_decode(proof));
    } catch (_) {
      return false;
    }
  }

  List<int> _hpkeInfo({
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
  }) => utf8.encode(
    'hyper-authenticator:v1:device-dek-wrap:'
    '$userId:$installationId:$deviceKeyId:$keyGeneration',
  );

  List<int> _hpkeAad({
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
    required List<int> publicKeyBytes,
  }) => utf8.encode(
    'hyper-authenticator:v1:device-dek-wrap-aad:'
    '$userId:$installationId:$deviceKeyId:$keyGeneration:'
    '${base64UrlEncode(publicKeyBytes)}',
  );

  List<int> _membershipContext({
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
    required List<int> publicKeyBytes,
  }) => utf8.encode(
    'hyper-authenticator:v1:device-membership:'
    '$userId:$installationId:$deviceKeyId:$keyGeneration:'
    '${base64UrlEncode(publicKeyBytes)}',
  );

  void _validateContext({
    required List<int> dataKeyBytes,
    required List<int> publicKeyBytes,
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
  }) {
    _requireKey(dataKeyBytes, 'Vault data key');
    _requireKey(publicKeyBytes, 'Device public key');
    if (userId.trim().isEmpty ||
        installationId.trim().isEmpty ||
        deviceKeyId.trim().isEmpty ||
        keyGeneration < 1) {
      throw const DeviceKeyCryptoException('Device key context không hợp lệ.');
    }
  }

  void _validateEnvelope(DeviceWrappedVaultKey wrappedKey) {
    if (wrappedKey.formatVersion !=
            DeviceWrappedVaultKey.currentFormatVersion ||
        wrappedKey.keyGeneration < 1 ||
        wrappedKey.kem != DeviceWrappedVaultKey.kemName ||
        wrappedKey.kdf != DeviceWrappedVaultKey.kdfName ||
        wrappedKey.aead != DeviceWrappedVaultKey.aeadName) {
      throw const DeviceKeyCryptoException(
        'Device-wrapped key version hoặc suite không được hỗ trợ.',
      );
    }
  }

  List<int> _decode(String value) {
    try {
      return base64Url.decode(value);
    } catch (_) {
      throw const DeviceKeyCryptoException(
        'Device-wrapped key encoding không hợp lệ.',
      );
    }
  }

  void _requireKey(List<int> bytes, String field) {
    if (bytes.length != _keyLength) {
      throw DeviceKeyCryptoException('$field phải có 256 bit.');
    }
  }
}
