import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';

abstract class AuthenticatorDeviceSessionRepository {
  Future<Either<Failure, List<AuthenticatorDeviceSession>>> load({
    required String userId,
  });

  Future<Either<Failure, void>> revoke({
    required String userId,
    required String registrationId,
  });
}
