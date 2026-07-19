import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_snapshot.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';

abstract class EncryptedVaultRepository {
  Future<Either<Failure, EncryptedVaultSnapshot?>> download({
    required String userId,
  });

  Future<Either<Failure, int>> publish({
    required String userId,
    required int expectedRevision,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  });

  Future<Either<Failure, int>> publishV2({
    required String userId,
    required int expectedRevision,
    required int expectedKeyGeneration,
    required List<int> bindingSecretBytes,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  });

  Future<Either<Failure, int>> rotateDeviceKeys({
    required String userId,
    required int expectedRevision,
    required int expectedKeyGeneration,
    required List<int> bindingSecretBytes,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
    required String nextVaultMembershipVerifier,
    required List<DeviceKeyRotationWrap> deviceWraps,
    required List<String> excludedDeviceKeyIds,
  });
}
