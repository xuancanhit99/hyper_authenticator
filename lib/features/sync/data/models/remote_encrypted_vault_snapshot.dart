import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';

class RemoteEncryptedVaultSnapshot {
  final EncryptedVaultEnvelope envelope;
  final WrappedVaultKey wrappedDataKey;
  final DateTime updatedAt;

  const RemoteEncryptedVaultSnapshot({
    required this.envelope,
    required this.wrappedDataKey,
    required this.updatedAt,
  });

  factory RemoteEncryptedVaultSnapshot.fromRow(Map<String, dynamic> row) {
    final updatedAtValue = row['updated_at'];
    if (updatedAtValue is! String) {
      throw const FormatException('Encrypted snapshot timestamp không hợp lệ.');
    }
    final updatedAt = DateTime.tryParse(updatedAtValue);
    if (updatedAt == null) {
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
