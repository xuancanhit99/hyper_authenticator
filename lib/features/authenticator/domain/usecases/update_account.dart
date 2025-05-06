import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:equatable/equatable.dart'; // Import Equatable

@lazySingleton
class UpdateAccount implements UseCase<Unit, UpdateAccountParams> {
  final AuthenticatorRepository repository;

  UpdateAccount(this.repository);

  @override
  Future<Either<Failure, Unit>> call(UpdateAccountParams params) async {
    return await repository.updateAccount(params.account);
  }
}

class UpdateAccountParams extends Equatable {
  final AuthenticatorAccount account;

  const UpdateAccountParams({required this.account});

  @override
  List<Object?> get props => [account];
}
