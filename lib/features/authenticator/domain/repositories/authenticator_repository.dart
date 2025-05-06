import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart'; // Assuming a common Failure class exists
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

abstract class AuthenticatorRepository {
  /// Retrieves a list of all stored authenticator accounts.
  /// Returns [Right] with the list of accounts on success.
  /// Returns [Left] with a [Failure] on error (e.g., StorageFailure).
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts();

  /// Adds a new authenticator account.
  /// Takes the account details (issuer, name, secret) potentially parsed from URI.
  /// Returns [Right] with the newly saved [AuthenticatorAccount] (including its generated ID) on success.
  /// Returns [Left] with a [Failure] on error.
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm, // Added
    required int digits, // Added
    required int period, // Added
  });

  /// Deletes an authenticator account by its ID.
  /// Returns [Right(unit)] on successful deletion.
  /// Returns [Left] with a [Failure] if the account is not found or deletion fails.
  Future<Either<Failure, Unit>> deleteAccount(String id);

  /// Updates an existing authenticator account.
  /// Returns [Right(unit)] on successful update.
  /// Returns [Left] with a [Failure] if the account is not found or update fails.
  Future<Either<Failure, Unit>> updateAccount(AuthenticatorAccount account);

  // Note: Generating the TOTP code itself is often considered a domain/usecase logic
  // rather than a repository function, as it doesn't involve data persistence.
  // We will create a separate use case for that later.
}
