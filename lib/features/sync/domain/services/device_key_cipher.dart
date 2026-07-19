import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/services/hpke_base_cipher.dart';
import 'package:injectable/injectable.dart';

class DeviceKeyCryptoException implements Exception {
  final String message;

  const DeviceKeyCryptoException(this.message);

  @override
  String toString() => 'DeviceKeyCryptoException: $message';
}

@lazySingleton
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
    SimpleKeyPair? keyPair;
    SimpleKeyPairData? extractedKeyPair;
    SecretKey? bindingSecretKey;
    try {
      keyPair = await _keyExchange.newKeyPair();
      extractedKeyPair = await keyPair.extract();
      final publicKey = await keyPair.extractPublicKey();
      bindingSecretKey = await _randomKeySource.newSecretKey();
      final bindingSecret = await bindingSecretKey.extractBytes();
      return DeviceKeyMaterial(
        privateKeyBytes: extractedKeyPair.bytes,
        publicKeyBytes: publicKey.bytes,
        bindingSecretBytes: bindingSecret,
      );
    } catch (_) {
      throw const DeviceKeyCryptoException(
        'Không thể tạo device key material.',
      );
    } finally {
      extractedKeyPair?.destroy();
      keyPair?.destroy();
      bindingSecretKey?.destroy();
    }
  }

  Future<List<int>> publicKeyForPrivateKey(List<int> privateKeyBytes) async {
    _requireKey(privateKeyBytes, 'Device private key');
    SimpleKeyPair? keyPair;
    try {
      keyPair = await _keyExchange.newKeyPairFromSeed(privateKeyBytes);
      return List<int>.unmodifiable((await keyPair.extractPublicKey()).bytes);
    } catch (_) {
      throw const DeviceKeyCryptoException('Device private key không hợp lệ.');
    } finally {
      keyPair?.destroy();
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
      final encapsulatedKey = _decodeExact(
        wrappedKey.encapsulatedKey,
        expectedLength: 32,
        field: 'Encapsulated key',
      );
      final ciphertext = _decodeExact(
        wrappedKey.ciphertext,
        expectedLength: _keyLength,
        field: 'Wrapped ciphertext',
      );
      final authTag = _decodeExact(
        wrappedKey.authTag,
        expectedLength: 16,
        field: 'Authentication tag',
      );
      final clearText = await _hpke.open(
        recipientPrivateKey: recipientPrivateKeyBytes,
        sealed: HpkeCiphertext(
          encapsulatedKey: encapsulatedKey,
          ciphertext: ciphertext,
          authTag: authTag,
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
    final dataKey = SecretKey(dataKeyBytes);
    SecretKey? proofKey;
    try {
      proofKey = await _membershipKdf.deriveKey(
        secretKey: dataKey,
        nonce: _contextBytes(
          label: 'hyper-authenticator:v1:device-membership-kdf',
          fields: <List<int>>[
            utf8.encode(userId),
            utf8.encode(keyGeneration.toString()),
          ],
        ),
        info: context,
      );
      final proof = await _membershipMac.calculateMac(
        context,
        secretKey: proofKey,
      );
      return base64UrlEncode(proof.bytes);
    } finally {
      proofKey?.destroy();
      dataKey.destroy();
    }
  }

  Future<String> createVaultMembershipVerifier({
    required List<int> dataKeyBytes,
    required String userId,
    required int keyGeneration,
  }) async {
    _requireKey(dataKeyBytes, 'Vault data key');
    if (!_isValidIdentifier(userId) || keyGeneration < 1) {
      throw const DeviceKeyCryptoException(
        'Vault membership context không hợp lệ.',
      );
    }
    final context = _contextBytes(
      label: 'hyper-authenticator:v1:vault-membership-verifier',
      fields: <List<int>>[
        utf8.encode(userId),
        utf8.encode(keyGeneration.toString()),
      ],
    );
    final dataKey = SecretKey(dataKeyBytes);
    SecretKey? verifierKey;
    try {
      verifierKey = await _membershipKdf.deriveKey(
        secretKey: dataKey,
        nonce: _contextBytes(
          label: 'hyper-authenticator:v1:vault-membership-kdf',
          fields: <List<int>>[
            utf8.encode(userId),
            utf8.encode(keyGeneration.toString()),
          ],
        ),
        info: context,
      );
      final verifier = await _membershipMac.calculateMac(
        context,
        secretKey: verifierKey,
      );
      return base64UrlEncode(verifier.bytes);
    } finally {
      verifierKey?.destroy();
      dataKey.destroy();
    }
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
  }) => _contextBytes(
    label: 'hyper-authenticator:v1:device-dek-wrap',
    fields: <List<int>>[
      utf8.encode(userId),
      utf8.encode(installationId),
      utf8.encode(deviceKeyId),
      utf8.encode(keyGeneration.toString()),
    ],
  );

  List<int> _hpkeAad({
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
    required List<int> publicKeyBytes,
  }) => _contextBytes(
    label: 'hyper-authenticator:v1:device-dek-wrap-aad',
    fields: <List<int>>[
      utf8.encode(userId),
      utf8.encode(installationId),
      utf8.encode(deviceKeyId),
      utf8.encode(keyGeneration.toString()),
      publicKeyBytes,
    ],
  );

  List<int> _membershipContext({
    required String userId,
    required String installationId,
    required String deviceKeyId,
    required int keyGeneration,
    required List<int> publicKeyBytes,
  }) => _contextBytes(
    label: 'hyper-authenticator:v1:device-membership',
    fields: <List<int>>[
      utf8.encode(userId),
      utf8.encode(installationId),
      utf8.encode(deviceKeyId),
      utf8.encode(keyGeneration.toString()),
      publicKeyBytes,
    ],
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
    if (!_isValidIdentifier(userId) ||
        !_isValidIdentifier(installationId) ||
        !_isValidIdentifier(deviceKeyId) ||
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

  List<int> _decodeExact(
    String value, {
    required int expectedLength,
    required String field,
  }) {
    final expectedEncodedLength = ((expectedLength + 2) ~/ 3) * 4;
    if (value.length != expectedEncodedLength) {
      throw DeviceKeyCryptoException('$field có độ dài không hợp lệ.');
    }
    final decoded = _decode(value);
    if (decoded.length != expectedLength || base64UrlEncode(decoded) != value) {
      throw DeviceKeyCryptoException('$field encoding không canonical.');
    }
    return decoded;
  }

  List<int> _contextBytes({
    required String label,
    required List<List<int>> fields,
  }) {
    final output = <int>[];
    for (final field in <List<int>>[utf8.encode(label), ...fields]) {
      output.addAll(<int>[
        (field.length >> 24) & 0xff,
        (field.length >> 16) & 0xff,
        (field.length >> 8) & 0xff,
        field.length & 0xff,
      ]);
      output.addAll(field);
    }
    return List<int>.unmodifiable(output);
  }

  bool _isValidIdentifier(String value) {
    final encoded = utf8.encode(value);
    return value.trim().isNotEmpty && encoded.length <= 256;
  }

  void _requireKey(List<int> bytes, String field) {
    if (bytes.length != _keyLength) {
      throw DeviceKeyCryptoException('$field phải có 256 bit.');
    }
  }
}
