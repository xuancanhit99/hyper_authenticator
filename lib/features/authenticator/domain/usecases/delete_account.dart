import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:injectable/injectable.dart'; // Add import

@injectable // Register use case
class DeleteAccount implements UseCase<Unit, DeleteAccountParams> {
  final AuthenticatorRepository repository;

  DeleteAccount(this.repository);

  @override
  Future<Either<Failure, Unit>> call(DeleteAccountParams params) async {
    if (params.accountId.isEmpty) {
      // Use the ValidationFailure defined in add_account.dart or move it to core/error/failures.dart
      // For now, assuming it's accessible or redefined here if needed.
      // class ValidationFailure extends Failure { const ValidationFailure(String message) : super(message); }
      return Left(ValidationFailure('Account ID cannot be empty.'));
    }
    return await repository.deleteAccount(params.accountId);
  }
}

class DeleteAccountParams extends Equatable {
  final String accountId;

  const DeleteAccountParams({required this.accountId});

  @override
  List<Object?> get props => [accountId];
}

// ValidationFailure is imported from core/error/failures.dart
