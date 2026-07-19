import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';

class EncryptedVaultSnapshot {
  final EncryptedVaultEnvelope envelope;
  final WrappedVaultKey wrappedDataKey;
  final DateTime updatedAt;
  final int keyGeneration;
  final int deviceWrapVersion;

  const EncryptedVaultSnapshot({
    required this.envelope,
    required this.wrappedDataKey,
    required this.updatedAt,
    this.keyGeneration = 1,
    this.deviceWrapVersion = 0,
  });
}
