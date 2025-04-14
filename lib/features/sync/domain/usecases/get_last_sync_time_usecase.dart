import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class GetLastSyncTimeUseCase implements UseCase<DateTime?, NoParams> {
  final SyncRepository repository;

  GetLastSyncTimeUseCase(this.repository);

  @override
  Future<Either<Failure, DateTime?>> call(NoParams params) async {
    return await repository.getLastSyncTime();
  }
}
