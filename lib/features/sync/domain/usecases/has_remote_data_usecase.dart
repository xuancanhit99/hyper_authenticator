import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class HasRemoteDataUseCase implements UseCase<bool, NoParams> {
  final SyncRepository syncRepository;

  HasRemoteDataUseCase(this.syncRepository);

  @override
  Future<Either<Failure, bool>> call(NoParams params) async {
    return await syncRepository.hasRemoteData();
  }
}
