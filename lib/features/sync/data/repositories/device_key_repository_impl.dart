import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/device_key_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@LazySingleton(as: DeviceKeyRepository)
class DeviceKeyRepositoryImpl implements DeviceKeyRepository {
  final DeviceKeyRemoteDataSource _remote;

  DeviceKeyRepositoryImpl(this._remote);

  @override
  Future<Either<Failure, DeviceKeyEnrollment>> beginEnrollment({
    required String userId,
    required String installationId,
    required List<int> publicKeyBytes,
    required List<int> bindingSecretBytes,
  }) => _run(
    () => _remote.beginEnrollment(
      userId: userId,
      installationId: installationId,
      publicKeyBytes: publicKeyBytes,
      bindingSecretBytes: bindingSecretBytes,
    ),
  );

  @override
  Future<Either<Failure, List<AuthenticatorDeviceKey>>> list({
    required String userId,
  }) => _run(() => _remote.list(userId: userId));

  @override
  Future<Either<Failure, void>> publishWrap({
    required String userId,
    required String targetDeviceKeyId,
    required List<int> bindingSecretBytes,
    required DeviceWrappedVaultKey wrappedKey,
    required String vaultMembershipVerifier,
    required String membershipProof,
  }) => _run(
    () => _remote.publishWrap(
      userId: userId,
      targetDeviceKeyId: targetDeviceKeyId,
      bindingSecretBytes: bindingSecretBytes,
      wrappedKey: wrappedKey,
      vaultMembershipVerifier: vaultMembershipVerifier,
      membershipProof: membershipProof,
    ),
  );

  @override
  Future<Either<Failure, void>> confirmCurrent({
    required String userId,
    required String deviceKeyId,
    required List<int> bindingSecretBytes,
    required int keyGeneration,
  }) => _run(
    () => _remote.confirmCurrent(
      userId: userId,
      deviceKeyId: deviceKeyId,
      bindingSecretBytes: bindingSecretBytes,
      keyGeneration: keyGeneration,
    ),
  );

  Future<Either<Failure, T>> _run<T>(Future<T> Function() operation) async {
    try {
      return Right(await operation());
    } on DeviceKeyConflictException {
      return const Left(
        SyncRevisionConflictFailure(
          'Device key hoặc key generation đã thay đổi; hãy tải lại.',
        ),
      );
    } on DeviceKeyBindingException {
      return const Left(
        AuthCredentialsFailure(
          'Thiết bị hiện tại chưa có binding hợp lệ hoặc phiên đã bị thu hồi.',
        ),
      );
    } on AuthException {
      return const Left(AuthCredentialsFailure('Cần đăng nhập lại.'));
    } on ServerException catch (error) {
      return Left(ServerFailure(error.message));
    } catch (_) {
      return const Left(
        ServerFailure('Device key operation thất bại an toàn.'),
      );
    }
  }
}
