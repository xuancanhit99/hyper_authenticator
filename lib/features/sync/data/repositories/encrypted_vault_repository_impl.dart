import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/encrypted_vault_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_snapshot.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/encrypted_vault_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@LazySingleton(as: EncryptedVaultRepository)
class EncryptedVaultRepositoryImpl implements EncryptedVaultRepository {
  final EncryptedVaultRemoteDataSource _remote;

  EncryptedVaultRepositoryImpl(this._remote);

  @override
  Future<Either<Failure, EncryptedVaultSnapshot?>> download({
    required String userId,
  }) async {
    try {
      return Right(await _remote.download(userId: userId));
    } on AuthException {
      return const Left(AuthCredentialsFailure('Cần đăng nhập để đồng bộ.'));
    } on ServerException catch (error) {
      return Left(ServerFailure(error.message));
    } catch (_) {
      return const Left(
        ServerFailure('Không thể đọc encrypted vault từ server.'),
      );
    }
  }

  @override
  Future<Either<Failure, int>> publish({
    required String userId,
    required int expectedRevision,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  }) async {
    try {
      return Right(
        await _remote.publish(
          userId: userId,
          expectedRevision: expectedRevision,
          envelope: envelope,
          wrappedDataKey: wrappedDataKey,
        ),
      );
    } on EncryptedVaultRevisionConflictException {
      return const Left(
        SyncRevisionConflictFailure(
          'Cloud vault đã thay đổi trên thiết bị khác.',
        ),
      );
    } on AuthException {
      return const Left(AuthCredentialsFailure('Cần đăng nhập để đồng bộ.'));
    } on ServerException catch (error) {
      return Left(ServerFailure(error.message));
    } catch (_) {
      return const Left(
        ServerFailure('Không thể publish encrypted vault lên server.'),
      );
    }
  }

  @override
  Future<Either<Failure, int>> publishV2({
    required String userId,
    required int expectedRevision,
    required int expectedKeyGeneration,
    required List<int> bindingSecretBytes,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  }) => _publish(
    () => _remote.publishV2(
      userId: userId,
      expectedRevision: expectedRevision,
      expectedKeyGeneration: expectedKeyGeneration,
      bindingSecretBytes: bindingSecretBytes,
      envelope: envelope,
      wrappedDataKey: wrappedDataKey,
    ),
  );

  @override
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
  }) => _publish(
    () => _remote.rotateDeviceKeys(
      userId: userId,
      expectedRevision: expectedRevision,
      expectedKeyGeneration: expectedKeyGeneration,
      bindingSecretBytes: bindingSecretBytes,
      envelope: envelope,
      wrappedDataKey: wrappedDataKey,
      nextVaultMembershipVerifier: nextVaultMembershipVerifier,
      deviceWraps: deviceWraps,
      excludedDeviceKeyIds: excludedDeviceKeyIds,
    ),
  );

  Future<Either<Failure, int>> _publish(Future<int> Function() action) async {
    try {
      return Right(await action());
    } on EncryptedVaultRevisionConflictException {
      return const Left(
        SyncRevisionConflictFailure(
          'Cloud vault đã thay đổi trên thiết bị khác.',
        ),
      );
    } on AuthException {
      return const Left(
        AuthCredentialsFailure(
          'Thiết bị chưa được xác minh hoặc cần đăng nhập lại.',
        ),
      );
    } on ServerException catch (error) {
      return Left(ServerFailure(error.message));
    } catch (_) {
      return const Left(
        ServerFailure('Không thể publish encrypted vault lên server.'),
      );
    }
  }
}
