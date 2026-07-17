import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:injectable/injectable.dart';

class VaultCryptoException implements Exception {
  final String message;

  const VaultCryptoException(this.message);

  @override
  String toString() => 'VaultCryptoException: $message';
}

@lazySingleton
class VaultCipher {
  static const _recoveryPrefix = 'HA1-';
  static const _keyLength = 32;
  final AesGcm _algorithm;

  VaultCipher() : _algorithm = AesGcm.with256bits();

  VaultCipher.withAlgorithm(this._algorithm);

  Future<VaultKeyBundle> createKeyBundle({required String userId}) async {
    _requireUserId(userId);
    final dataKeyBytes = await (await _algorithm.newSecretKey()).extractBytes();
    final recoveryKeyBytes = await (await _algorithm.newSecretKey())
        .extractBytes();
    final recoveryCode = _encodeRecoveryCode(recoveryKeyBytes);
    final wrappedDataKey = await wrapDataKey(
      dataKeyBytes: dataKeyBytes,
      recoveryCode: recoveryCode,
      userId: userId,
    );
    return VaultKeyBundle(
      dataKeyBytes: List<int>.unmodifiable(dataKeyBytes),
      recoveryCode: recoveryCode,
      wrappedDataKey: wrappedDataKey,
    );
  }

  Future<WrappedVaultKey> wrapDataKey({
    required List<int> dataKeyBytes,
    required String recoveryCode,
    required String userId,
  }) async {
    _requireUserId(userId);
    _requireKeyBytes(dataKeyBytes);
    final recoveryKeyBytes = _decodeRecoveryCode(recoveryCode);
    final secretBox = await _algorithm.encrypt(
      dataKeyBytes,
      secretKey: SecretKey(recoveryKeyBytes),
      nonce: _algorithm.newNonce(),
      aad: _wrapAad(userId),
    );
    return WrappedVaultKey(
      formatVersion: WrappedVaultKey.currentFormatVersion,
      cipher: EncryptedVaultEnvelope.cipherName,
      nonce: base64UrlEncode(secretBox.nonce),
      ciphertext: base64UrlEncode(secretBox.cipherText),
      authTag: base64UrlEncode(secretBox.mac.bytes),
    );
  }

  Future<List<int>> unwrapDataKey({
    required WrappedVaultKey wrappedKey,
    required String recoveryCode,
    required String userId,
  }) async {
    _requireUserId(userId);
    _validateWrappedKeyMetadata(wrappedKey);
    try {
      final clearText = await _algorithm.decrypt(
        _toSecretBox(
          nonce: wrappedKey.nonce,
          ciphertext: wrappedKey.ciphertext,
          authTag: wrappedKey.authTag,
        ),
        secretKey: SecretKey(_decodeRecoveryCode(recoveryCode)),
        aad: _wrapAad(userId),
      );
      _requireKeyBytes(clearText);
      return List<int>.unmodifiable(clearText);
    } on VaultCryptoException {
      rethrow;
    } catch (_) {
      throw const VaultCryptoException(
        'Không thể mở vault key; recovery key hoặc metadata không hợp lệ.',
      );
    }
  }

  Future<EncryptedVaultEnvelope> encryptAccounts({
    required List<AuthenticatorAccount> accounts,
    required List<int> dataKeyBytes,
    required String userId,
    required int revision,
  }) async {
    _requireUserId(userId);
    _requireKeyBytes(dataKeyBytes);
    if (revision < 1) {
      throw const VaultCryptoException('Revision phải lớn hơn 0.');
    }

    final sortedAccounts = List<AuthenticatorAccount>.from(accounts)
      ..sort((left, right) => left.id.compareTo(right.id));
    final payload = utf8.encode(
      jsonEncode(<String, dynamic>{
        'format_version': 1,
        'accounts': sortedAccounts.map((account) => account.toJson()).toList(),
      }),
    );
    final secretBox = await _algorithm.encrypt(
      payload,
      secretKey: SecretKey(dataKeyBytes),
      nonce: _algorithm.newNonce(),
      aad: _snapshotAad(userId, revision),
    );
    return EncryptedVaultEnvelope(
      formatVersion: EncryptedVaultEnvelope.currentFormatVersion,
      revision: revision,
      cipher: EncryptedVaultEnvelope.cipherName,
      nonce: base64UrlEncode(secretBox.nonce),
      ciphertext: base64UrlEncode(secretBox.cipherText),
      authTag: base64UrlEncode(secretBox.mac.bytes),
    );
  }

  Future<List<AuthenticatorAccount>> decryptAccounts({
    required EncryptedVaultEnvelope envelope,
    required List<int> dataKeyBytes,
    required String userId,
  }) async {
    _requireUserId(userId);
    _requireKeyBytes(dataKeyBytes);
    _validateEnvelopeMetadata(envelope);
    try {
      final clearText = await _algorithm.decrypt(
        _toSecretBox(
          nonce: envelope.nonce,
          ciphertext: envelope.ciphertext,
          authTag: envelope.authTag,
        ),
        secretKey: SecretKey(dataKeyBytes),
        aad: _snapshotAad(userId, envelope.revision),
      );
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map<String, dynamic> ||
          decoded['format_version'] != 1 ||
          decoded['accounts'] is! List<dynamic>) {
        throw const VaultCryptoException(
          'Plaintext snapshot có format không hợp lệ.',
        );
      }
      return (decoded['accounts'] as List<dynamic>)
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const VaultCryptoException('Account payload không hợp lệ.');
            }
            final account = AuthenticatorAccount.fromJson(item);
            _validateAccount(account);
            return account;
          })
          .toList(growable: false);
    } on VaultCryptoException {
      rethrow;
    } catch (_) {
      throw const VaultCryptoException(
        'Không thể xác thực hoặc giải mã encrypted vault.',
      );
    }
  }

  SecretBox _toSecretBox({
    required String nonce,
    required String ciphertext,
    required String authTag,
  }) {
    try {
      return SecretBox(
        base64Url.decode(ciphertext),
        nonce: base64Url.decode(nonce),
        mac: Mac(base64Url.decode(authTag)),
      );
    } catch (_) {
      throw const VaultCryptoException('Ciphertext encoding không hợp lệ.');
    }
  }

  void _validateEnvelopeMetadata(EncryptedVaultEnvelope envelope) {
    if (envelope.formatVersion != EncryptedVaultEnvelope.currentFormatVersion ||
        envelope.cipher != EncryptedVaultEnvelope.cipherName ||
        envelope.revision < 1) {
      throw const VaultCryptoException(
        'Encrypted vault version hoặc cipher không được hỗ trợ.',
      );
    }
  }

  void _validateWrappedKeyMetadata(WrappedVaultKey wrappedKey) {
    if (wrappedKey.formatVersion != WrappedVaultKey.currentFormatVersion ||
        wrappedKey.cipher != EncryptedVaultEnvelope.cipherName) {
      throw const VaultCryptoException(
        'Wrapped key version hoặc cipher không được hỗ trợ.',
      );
    }
  }

  void _validateAccount(AuthenticatorAccount account) {
    if (account.id.isEmpty ||
        account.issuer.trim().isEmpty ||
        account.accountName.trim().isEmpty) {
      throw const VaultCryptoException('Account identity không hợp lệ.');
    }
    try {
      TotpValidator.normalizeSecret(account.secretKey);
      TotpValidator.normalizeAlgorithm(account.algorithm);
      TotpValidator.validateParameters(
        digits: account.digits,
        period: account.period,
      );
    } on FormatException catch (error) {
      throw VaultCryptoException(error.message);
    }
  }

  List<int> _snapshotAad(String userId, int revision) =>
      utf8.encode('hyper-authenticator:v1:vault-snapshot:$userId:$revision');

  List<int> _wrapAad(String userId) =>
      utf8.encode('hyper-authenticator:v1:dek-wrap:$userId');

  String _encodeRecoveryCode(List<int> bytes) =>
      '$_recoveryPrefix${base64UrlEncode(bytes).replaceAll('=', '')}';

  List<int> _decodeRecoveryCode(String recoveryCode) {
    if (!recoveryCode.startsWith(_recoveryPrefix)) {
      throw const VaultCryptoException('Recovery key prefix không hợp lệ.');
    }
    final encoded = recoveryCode.substring(_recoveryPrefix.length);
    final padding = '=' * ((4 - encoded.length % 4) % 4);
    try {
      final bytes = base64Url.decode('$encoded$padding');
      _requireKeyBytes(bytes);
      return bytes;
    } catch (_) {
      throw const VaultCryptoException('Recovery key không hợp lệ.');
    }
  }

  void _requireKeyBytes(List<int> bytes) {
    if (bytes.length != _keyLength) {
      throw const VaultCryptoException('Vault key phải có 256 bit.');
    }
  }

  void _requireUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw const VaultCryptoException('User identity không hợp lệ.');
    }
  }
}
