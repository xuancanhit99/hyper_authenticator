import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

// Removed import for non-existent EncryptedAccount
/// Abstract class defining the contract for repositories
/// responsible for synchronizing authenticator accounts.
abstract class SyncRepository {
  /// Uploads a list of authenticator accounts to the remote storage.
  ///
  /// Returns [Right(unit)] on success, or [Left(Failure)] on error.
  Future<Either<Failure, Unit>> uploadAccounts(
    List<AuthenticatorAccount> accounts,
  );

  /// Downloads a list of authenticator accounts from the remote storage
  /// for the current user.
  ///
  /// Returns [Right(List<AuthenticatorAccount>)] on success,
  /// or [Left(Failure)] on error.
  Future<Either<Failure, List<AuthenticatorAccount>>> downloadAccounts();

  /// Checks if there is any sync data available on the remote storage
  /// for the current user.
  ///
  /// Returns [Right(bool)] indicating if data exists,
  /// or [Left(Failure)] on error.
  Future<Either<Failure, bool>> hasRemoteData();

  /// Fetches the timestamp of the last successful sync for the current user.
  /// Returns [Right(DateTime?)] with the timestamp or null.
  /// Returns [Left(Failure)] on communication error.
  Future<Either<Failure, DateTime?>> getLastSyncTime();

  /// Saves the user's generated salt for encryption remotely.
  /// Returns [Right(unit)] on success, or [Left(Failure)] on error.
  Future<Either<Failure, Unit>> saveUserSalt(String salt);
  // Future<Either<Failure, List<EncryptedAccount>>> downloadEncryptedAccounts(); // Commented out as EncryptedAccount doesn't exist
}
