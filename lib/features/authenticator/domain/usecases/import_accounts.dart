import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:injectable/injectable.dart';

@injectable
class ImportAccounts
    implements UseCase<AccountImportSummary, ImportAccountsParams> {
  const ImportAccounts(this.repository);

  final AuthenticatorRepository repository;

  @override
  Future<Either<Failure, AccountImportSummary>> call(
    ImportAccountsParams params,
  ) async {
    if (params.accounts.isEmpty) {
      return const Left(ValidationFailure('Không có tài khoản nào để import.'));
    }

    final validated = <AuthenticatorAccount>[];
    try {
      for (final account in params.accounts) {
        final issuer = account.issuer.trim();
        final accountName = account.accountName.trim();
        if (issuer.isEmpty || accountName.isEmpty) {
          throw const FormatException(
            'Issuer và tên tài khoản không được để trống.',
          );
        }
        final secret = TotpValidator.normalizeSecret(account.secretKey);
        final algorithm = TotpValidator.normalizeAlgorithm(account.algorithm);
        TotpValidator.validateParameters(
          digits: account.digits,
          period: account.period,
        );
        validated.add(
          AuthenticatorAccount(
            id: '',
            issuer: issuer,
            accountName: accountName,
            secretKey: secret,
            algorithm: algorithm,
            digits: account.digits,
            period: account.period,
          ),
        );
      }
    } on FormatException catch (error) {
      return Left(ValidationFailure(error.message));
    }

    return repository.importAccounts(validated);
  }
}

class ImportAccountsParams extends Equatable {
  ImportAccountsParams(List<ParsedTotpAccount> accounts)
    : accounts = List<ParsedTotpAccount>.unmodifiable(accounts);

  final List<ParsedTotpAccount> accounts;

  @override
  List<Object?> get props => [accounts];

  @override
  String toString() =>
      'ImportAccountsParams(accounts: [${accounts.length} REDACTED])';
}
