import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/sync_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart'; // Assuming you use injectable

@LazySingleton(as: SyncRepository) // Assuming you use injectable
class SyncRepositoryImpl implements SyncRepository {
  final SyncRemoteDataSource remoteDataSource;
  // final NetworkInfo networkInfo; // Optional: Add if network check is needed

  SyncRepositoryImpl({
    required this.remoteDataSource,
    // required this.networkInfo,
  });

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> downloadAccounts() async {
    // TODO: Implement network check if needed
    try {
      final remoteAccounts = await remoteDataSource.downloadAccounts();
      return Right(remoteAccounts);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message ?? 'Failed to download accounts'));
    } catch (e) {
      // Catch other potential errors (e.g., unexpected format)
      return Left(
        ServerFailure(
          'An unexpected error occurred during download: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> uploadAccounts(
    List<AuthenticatorAccount> accounts,
  ) async {
    // TODO: Implement network check if needed
    try {
      await remoteDataSource.uploadAccounts(accounts);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message ?? 'Failed to upload accounts'));
    } catch (e) {
      return Left(
        ServerFailure(
          'An unexpected error occurred during upload: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> hasRemoteData() async {
    // TODO: Implement network check if needed
    try {
      final hasData = await remoteDataSource.hasRemoteData();
      return Right(hasData);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message ?? 'Failed to check remote data'));
    } catch (e) {
      return Left(
        ServerFailure(
          'An unexpected error occurred while checking remote data: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, DateTime?>> getLastUploadTime() async {
    // Renamed method
    // TODO: Implement network check if needed
    try {
      // Call the renamed method on the data source
      final lastUploadTime = await remoteDataSource.getLastUploadTime();
      return Right(lastUploadTime);
    } on ServerException catch (e) {
      // Return failure only for critical communication errors, not if timestamp is just null
      return Left(ServerFailure(e.message ?? 'Failed to get last upload time'));
    } catch (e) {
      return Left(
        ServerFailure(
          'An unexpected error occurred while getting last upload time: ${e.toString()}',
        ),
      );
    }
  }

  // --- Added Placeholder Implementations ---

  @override
  Future<Either<Failure, Unit>> saveUserSalt(String salt) async {
    // TODO: Implement actual logic to save salt via remoteDataSource
    print(
      "SyncRepositoryImpl: saveUserSalt called with salt: $salt (Not Implemented)",
    );
    // For now, return a failure or success based on expected behavior if implemented
    // Assuming it should succeed if network is okay, but depends on data source impl.
    // Let's return failure until implemented.
    return Left(ServerFailure('saveUserSalt not implemented in repository'));
  }

  // @override // Commented out as the interface method is commented out
  // Future<Either<Failure, List<EncryptedAccount>>>
  // downloadEncryptedAccounts() async {
  //   // TODO: Implement actual logic to download encrypted accounts via remoteDataSource
  //   print(
  //     "SyncRepositoryImpl: downloadEncryptedAccounts called (Not Implemented)",
  //   );
  //   // For now, return failure.
  //   return Left(
  //     ServerFailure('downloadEncryptedAccounts not implemented in repository'),
  //   );
  // }
}
