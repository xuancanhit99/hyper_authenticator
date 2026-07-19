import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_device_session_remote_data_source.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_installation_identity_store.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:hyper_authenticator/features/settings/domain/repositories/authenticator_device_session_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@LazySingleton(as: AuthenticatorDeviceSessionRepository)
class AuthenticatorDeviceSessionRepositoryImpl
    implements AuthenticatorDeviceSessionRepository {
  final AuthenticatorDeviceSessionRemoteDataSource _remote;
  final AuthenticatorInstallationIdentityStore _identityStore;

  AuthenticatorDeviceSessionRepositoryImpl(this._remote, this._identityStore);

  @override
  Future<Either<Failure, List<AuthenticatorDeviceSession>>> load({
    required String userId,
  }) async {
    try {
      final identity = await _identityStore.readOrCreate();
      return Right(
        await _remote.registerAndList(userId: userId, identity: identity),
      );
    } on AuthException {
      return const Left(AuthCredentialsFailure('Cần đăng nhập lại.'));
    } on AuthServerException catch (error) {
      return Left(AuthCredentialsFailure(error.message));
    } on CacheException catch (error) {
      return Left(CacheFailure(error.message));
    } on ServerException catch (error) {
      return Left(ServerFailure(error.message));
    } catch (_) {
      return const Left(
        ServerFailure('Không thể tải danh sách thiết bị đã đăng nhập.'),
      );
    }
  }

  @override
  Future<Either<Failure, void>> revoke({
    required String userId,
    required String registrationId,
  }) async {
    try {
      await _remote.revoke(userId: userId, registrationId: registrationId);
      return const Right(null);
    } on AuthException {
      return const Left(AuthCredentialsFailure('Cần đăng nhập lại.'));
    } on AuthServerException catch (error) {
      return Left(AuthCredentialsFailure(error.message));
    } on ServerException catch (error) {
      return Left(ServerFailure(error.message));
    } catch (_) {
      return const Left(
        ServerFailure(
          'Không xác định được trạng thái thu hồi; hãy tải lại danh sách.',
        ),
      );
    }
  }
}
