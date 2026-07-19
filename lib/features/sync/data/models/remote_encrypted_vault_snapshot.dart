import 'dart:convert';

import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_snapshot.dart';

class RemoteEncryptedVaultSnapshot extends EncryptedVaultSnapshot {
  const RemoteEncryptedVaultSnapshot({
    required super.envelope,
    required super.wrappedDataKey,
    required super.updatedAt,
    required super.keyGeneration,
    required super.deviceWrapVersion,
  });

  factory RemoteEncryptedVaultSnapshot.fromRow(Map<String, dynamic> row) {
    final updatedAtValue = row['updated_at'];
    if (updatedAtValue is! String) {
      throw const FormatException('Encrypted snapshot timestamp không hợp lệ.');
    }
    final updatedAt = DateTime.tryParse(updatedAtValue);
    final keyGeneration = row['key_generation'] ?? 1;
    final deviceWrapVersion = row['device_wrap_version'] ?? 0;
    if (updatedAt == null ||
        keyGeneration is! int ||
        keyGeneration < 1 ||
        deviceWrapVersion is! int ||
        (deviceWrapVersion != 0 && deviceWrapVersion != 1)) {
      throw const FormatException('Encrypted snapshot timestamp không hợp lệ.');
    }
    return RemoteEncryptedVaultSnapshot(
      envelope: EncryptedVaultEnvelope.fromJson(row),
      wrappedDataKey: WrappedVaultKey.fromJson(<String, dynamic>{
        'format_version': row['key_format_version'],
        'cipher': row['cipher'],
        'nonce': row['wrapped_key_nonce'],
        'ciphertext': row['wrapped_key_ciphertext'],
        'auth_tag': row['wrapped_key_auth_tag'],
      }),
      updatedAt: updatedAt.toUtc(),
      keyGeneration: keyGeneration,
      deviceWrapVersion: deviceWrapVersion,
    );
  }
}

Map<String, dynamic> encryptedVaultPublishParameters({
  required int expectedRevision,
  required EncryptedVaultEnvelope envelope,
  required WrappedVaultKey wrappedDataKey,
}) => <String, dynamic>{
  'p_expected_revision': expectedRevision,
  'p_format_version': envelope.formatVersion,
  'p_cipher': envelope.cipher,
  'p_nonce': envelope.nonce,
  'p_ciphertext': envelope.ciphertext,
  'p_auth_tag': envelope.authTag,
  'p_key_format_version': wrappedDataKey.formatVersion,
  'p_wrapped_key_nonce': wrappedDataKey.nonce,
  'p_wrapped_key_ciphertext': wrappedDataKey.ciphertext,
  'p_wrapped_key_auth_tag': wrappedDataKey.authTag,
};

Map<String, dynamic> encryptedVaultPublishV2Parameters({
  required int expectedRevision,
  required int expectedKeyGeneration,
  required List<int> bindingSecretBytes,
  required EncryptedVaultEnvelope envelope,
  required WrappedVaultKey wrappedDataKey,
}) => <String, dynamic>{
  'p_expected_revision': expectedRevision,
  'p_expected_key_generation': expectedKeyGeneration,
  'p_current_binding_secret': base64UrlEncode(bindingSecretBytes),
  'p_format_version': envelope.formatVersion,
  'p_cipher': envelope.cipher,
  'p_nonce': envelope.nonce,
  'p_ciphertext': envelope.ciphertext,
  'p_auth_tag': envelope.authTag,
  'p_key_format_version': wrappedDataKey.formatVersion,
  'p_wrapped_key_nonce': wrappedDataKey.nonce,
  'p_wrapped_key_ciphertext': wrappedDataKey.ciphertext,
  'p_wrapped_key_auth_tag': wrappedDataKey.authTag,
};
