import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:injectable/injectable.dart'; // Add import

@injectable // Register use case
class AddAccount implements UseCase<AuthenticatorAccount, AddAccountParams> {
  final AuthenticatorRepository repository;

  AddAccount(this.repository);

  @override
  Future<Either<Failure, AuthenticatorAccount>> call(
    AddAccountParams params,
  ) async {
    final issuer = params.issuer.trim();
    final accountName = params.accountName.trim();
    if (issuer.isEmpty || accountName.isEmpty) {
      return Left(
        ValidationFailure('Issuer và tên tài khoản không được để trống.'),
      );
    }

    late final String secretKey;
    late final String algorithm;
    try {
      secretKey = TotpValidator.normalizeSecret(params.secretKey);
      algorithm = TotpValidator.normalizeAlgorithm(params.algorithm);
      TotpValidator.validateParameters(
        digits: params.digits,
        period: params.period,
      );
    } on FormatException catch (error) {
      return Left(ValidationFailure(error.message));
    }

    return repository.addAccount(
      issuer: issuer,
      accountName: accountName,
      secretKey: secretKey,
      algorithm: algorithm,
      digits: params.digits,
      period: params.period,
    );
  }
}

class AddAccountParams extends Equatable {
  final String issuer;
  final String accountName;
  final String secretKey;
  final String algorithm;
  final int digits;
  final int period;

  const AddAccountParams({
    required this.issuer,
    required this.accountName,
    required this.secretKey,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  @override
  List<Object?> get props => [
    issuer,
    accountName,
    secretKey,
    algorithm,
    digits,
    period,
  ];
}

// ValidationFailure is now defined in core/error/failures.dart
