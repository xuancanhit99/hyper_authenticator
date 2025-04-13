import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart'; // Assuming Failure and specific subtypes like StorageFailure exist
import 'package:hyper_authenticator/features/authenticator/data/datasources/authenticator_local_data_source.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';

import 'package:injectable/injectable.dart'; // Add import

// StorageFailure and AccountNotFoundFailure are now defined in core/error/failures.dart

@LazySingleton(as: AuthenticatorRepository) // Register as implementation
class AuthenticatorRepositoryImpl implements AuthenticatorRepository {
  final AuthenticatorLocalDataSource localDataSource;

  AuthenticatorRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async {
    try {
      final accounts = await localDataSource.getAccounts();
      return Right(accounts);
    } on StorageReadException {
      return const Left(
        StorageFailure(
          'Failed to read accounts from storage.',
        ), // Use positional argument
      );
    } catch (e) {
      // Catch any other unexpected errors
      return Left(
        StorageFailure(
          // Use positional argument
          'An unexpected error occurred while getting accounts: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
  }) async {
    try {
      // Create an account entity (ID will be generated by data source)
      final newAccount = AuthenticatorAccount(
        id: '', // ID will be generated by the data source
        issuer: issuer,
        accountName: accountName,
        secretKey: secretKey,
      );
      final savedAccount = await localDataSource.saveAccount(newAccount);
      return Right(savedAccount);
    } on StorageWriteException {
      return const Left(
        StorageFailure(
          'Failed to save account to storage.',
        ), // Use positional argument
      );
    } catch (e) {
      return Left(
        StorageFailure(
          // Use positional argument
          'An unexpected error occurred while adding account: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) async {
    try {
      await localDataSource.deleteAccount(id);
      return const Right(unit); // Use 'unit' from fpdart for void success
    } on AccountNotFoundException {
      return const Left(
        AccountNotFoundFailure('Account not found in storage.'),
      ); // Use positional argument
    } on StorageDeleteException {
      return const Left(
        StorageFailure(
          'Failed to delete account from storage.',
        ), // Use positional argument
      );
    } catch (e) {
      return Left(
        StorageFailure(
          // Use positional argument
          'An unexpected error occurred while deleting account: ${e.toString()}',
        ),
      );
    }
  }
}
