import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart';

// Consider renaming the file to get_last_upload_time_usecase.dart
@lazySingleton
class GetLastUploadTimeUseCase implements UseCase<DateTime?, NoParams> {
  // Renamed class
  final SyncRepository repository;

  GetLastUploadTimeUseCase(this.repository); // Renamed constructor

  @override
  Future<Either<Failure, DateTime?>> call(NoParams params) async {
    // Call the renamed repository method
    return await repository.getLastUploadTime();
  }
}
