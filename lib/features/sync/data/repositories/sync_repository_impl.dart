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
}
