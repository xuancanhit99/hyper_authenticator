import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart'; // Assuming a base UseCase class exists
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:injectable/injectable.dart'; // Add import

@injectable // Register use case
class GetAccounts implements UseCase<List<AuthenticatorAccount>, NoParams> {
  final AuthenticatorRepository repository;

  GetAccounts(this.repository);

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> call(
    NoParams params,
  ) async {
    return await repository.getAccounts();
  }
}
