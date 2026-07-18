import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';

class EncryptedVaultSnapshot {
  final EncryptedVaultEnvelope envelope;
  final WrappedVaultKey wrappedDataKey;
  final DateTime updatedAt;

  const EncryptedVaultSnapshot({
    required this.envelope,
    required this.wrappedDataKey,
    required this.updatedAt,
  });
}
