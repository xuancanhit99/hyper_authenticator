import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:injectable/injectable.dart';
import 'package:equatable/equatable.dart'; // Import Equatable

@lazySingleton
class UpdateAccount implements UseCase<Unit, UpdateAccountParams> {
  final AuthenticatorRepository repository;

  UpdateAccount(this.repository);

  @override
  Future<Either<Failure, Unit>> call(UpdateAccountParams params) async {
    final account = params.account;
    final issuer = account.issuer.trim();
    final accountName = account.accountName.trim();
    if (account.id.isEmpty || issuer.isEmpty || accountName.isEmpty) {
      return const Left(
        ValidationFailure('ID, issuer và tên tài khoản không được để trống.'),
      );
    }

    try {
      final normalizedAccount = AuthenticatorAccount(
        id: account.id,
        issuer: issuer,
        accountName: accountName,
        secretKey: TotpValidator.normalizeSecret(account.secretKey),
        algorithm: TotpValidator.normalizeAlgorithm(account.algorithm),
        digits: account.digits,
        period: account.period,
      );
      TotpValidator.validateParameters(
        digits: normalizedAccount.digits,
        period: normalizedAccount.period,
      );
      return repository.updateAccount(normalizedAccount);
    } on FormatException catch (error) {
      return Left(ValidationFailure(error.message));
    }
  }
}

class UpdateAccountParams extends Equatable {
  final AuthenticatorAccount account;

  const UpdateAccountParams({required this.account});

  @override
  List<Object?> get props => [account];
}
