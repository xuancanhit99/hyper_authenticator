import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:injectable/injectable.dart';

/// Merges downloaded records into the local vault by stable account ID.
///
/// This compatibility bridge deliberately keeps an existing local record when
/// the same ID is present remotely. Full conflict/deletion semantics require
/// the revisioned sync-v2 protocol.
@lazySingleton
class MergeAccountsUseCase {
  final AuthenticatorRepository repository;

  MergeAccountsUseCase(this.repository);

  Future<Either<Failure, List<AuthenticatorAccount>>> call(
    List<AuthenticatorAccount> remoteAccounts,
  ) async {
    final localResult = await repository.getAccounts();

    return localResult.fold((failure) async => Left(failure), (
      localAccounts,
    ) async {
      final mergedById = <String, AuthenticatorAccount>{
        for (final account in localAccounts) account.id: account,
      };

      for (final remoteAccount in remoteAccounts) {
        if (mergedById.containsKey(remoteAccount.id)) {
          continue;
        }

        final validated = _validateRemoteAccount(remoteAccount);
        Failure? validationFailure;
        AuthenticatorAccount? accountToSave;
        validated.fold(
          (failure) => validationFailure = failure,
          (account) => accountToSave = account,
        );
        if (validationFailure != null) {
          return Left(validationFailure!);
        }

        final saveResult = await repository.saveAccount(accountToSave!);
        Failure? saveFailure;
        AuthenticatorAccount? savedAccount;
        saveResult.fold(
          (failure) => saveFailure = failure,
          (account) => savedAccount = account,
        );
        if (saveFailure != null) {
          return Left(saveFailure!);
        }
        mergedById[savedAccount!.id] = savedAccount!;
      }

      return Right(mergedById.values.toList(growable: false));
    });
  }

  Either<Failure, AuthenticatorAccount> _validateRemoteAccount(
    AuthenticatorAccount account,
  ) {
    final issuer = account.issuer.trim();
    final accountName = account.accountName.trim();
    if (account.id.isEmpty || issuer.isEmpty || accountName.isEmpty) {
      return const Left(
        ValidationFailure('Remote account có ID hoặc label không hợp lệ.'),
      );
    }

    try {
      final normalized = AuthenticatorAccount(
        id: account.id,
        issuer: issuer,
        accountName: accountName,
        secretKey: TotpValidator.normalizeSecret(account.secretKey),
        algorithm: TotpValidator.normalizeAlgorithm(account.algorithm),
        digits: account.digits,
        period: account.period,
      );
      TotpValidator.validateParameters(
        digits: normalized.digits,
        period: normalized.period,
      );
      return Right(normalized);
    } on FormatException catch (error) {
      return Left(ValidationFailure(error.message));
    }
  }
}
