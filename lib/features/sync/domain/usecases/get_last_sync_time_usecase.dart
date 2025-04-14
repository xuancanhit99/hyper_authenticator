import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart';

// Renamed class to GetLastSyncTimeUseCase for consistency
@lazySingleton
class GetLastSyncTimeUseCase implements UseCase<DateTime?, NoParams> {
  // Renamed class
  // Renamed class
  final SyncRepository repository;

  GetLastSyncTimeUseCase(this.repository); // Renamed constructor

  @override
  Future<Either<Failure, DateTime?>> call(NoParams params) async {
    // Call the renamed repository method
    // Assuming the repository method still reflects the underlying data source (e.g., upload timestamp)
    // If the repository method should also be renamed, that needs a separate change in the repository interface/impl.
    return await repository.getLastUploadTime();
  }
}
