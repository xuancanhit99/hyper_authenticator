import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:injectable/injectable.dart'; // Add import

@injectable // Register use case
class AddAccount implements UseCase<AuthenticatorAccount, AddAccountParams> {
  final AuthenticatorRepository repository;

  AddAccount(this.repository);

  @override
  Future<Either<Failure, AuthenticatorAccount>> call(
    AddAccountParams params,
  ) async {
    // Basic validation could be added here if needed
    if (params.secretKey.isEmpty ||
        params.issuer.isEmpty ||
        params.accountName.isEmpty) {
      return Left(
        ValidationFailure(
          'Issuer, Account Name, and Secret Key cannot be empty.',
        ),
      );
    }
    // Add more specific secret key validation (e.g., Base32 check) if desired

    return await repository.addAccount(
      issuer: params.issuer,
      accountName: params.accountName,
      secretKey: params.secretKey,
    );
  }
}

class AddAccountParams extends Equatable {
  final String issuer;
  final String accountName;
  final String secretKey;

  const AddAccountParams({
    required this.issuer,
    required this.accountName,
    required this.secretKey,
  });

  @override
  List<Object?> get props => [issuer, accountName, secretKey];
}

// ValidationFailure is now defined in core/error/failures.dart
