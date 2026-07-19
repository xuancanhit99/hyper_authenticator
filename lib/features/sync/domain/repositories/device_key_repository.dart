import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';

abstract class DeviceKeyRepository {
  Future<Either<Failure, DeviceKeyEnrollment>> beginEnrollment({
    required String userId,
    required String installationId,
    required List<int> publicKeyBytes,
    required List<int> bindingSecretBytes,
    required String vaultMembershipVerifier,
  });

  Future<Either<Failure, List<AuthenticatorDeviceKey>>> list({
    required String userId,
  });

  Future<Either<Failure, void>> publishWrap({
    required String userId,
    required String targetDeviceKeyId,
    required List<int> bindingSecretBytes,
    required DeviceWrappedVaultKey wrappedKey,
    required String vaultMembershipVerifier,
    required String membershipProof,
  });

  Future<Either<Failure, void>> confirmCurrent({
    required String userId,
    required String deviceKeyId,
    required List<int> bindingSecretBytes,
    required int keyGeneration,
  });
}
