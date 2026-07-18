import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';

abstract class VaultKeyRepository {
  Future<Either<Failure, List<int>?>> read(String userId);

  Future<Either<Failure, Unit>> write(String userId, List<int> dataKeyBytes);

  Future<Either<Failure, Unit>> delete(String userId);
}
