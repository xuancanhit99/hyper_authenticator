import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

/// Abstract class defining the contract for remote data sources
/// responsible for synchronizing authenticator accounts.
abstract class SyncRemoteDataSource {
  /// Uploads a list of authenticator accounts to the remote server.
  ///
  /// Throws a [ServerException] for all error codes.
  Future<void> uploadAccounts(List<AuthenticatorAccount> accounts);

  /// Downloads a list of authenticator accounts from the remote server
  /// for the current user.
  ///
  /// Returns a list of [AuthenticatorAccount].
  /// Throws a [ServerException] for all error codes.
  Future<List<AuthenticatorAccount>> downloadAccounts();

  /// Checks if there is any sync data available on the remote server
  /// for the current user.
  ///
  /// Returns `true` if data exists, `false` otherwise.
  /// Throws a [ServerException] for all error codes.
  Future<bool> hasRemoteData();

  /// Fetches the timestamp of the last successful upload for the current user
  /// by checking the latest 'updated_at' timestamp in their synced accounts.
  /// Returns [DateTime] or null if no accounts have been uploaded.
  /// Throws a [ServerException] for communication errors.
  Future<DateTime?> getLastUploadTime();
}
