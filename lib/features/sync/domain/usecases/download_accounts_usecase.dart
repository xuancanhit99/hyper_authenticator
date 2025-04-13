import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class DownloadAccountsUseCase
    implements UseCase<List<AuthenticatorAccount>, NoParams> {
  final SyncRepository syncRepository;

  DownloadAccountsUseCase(this.syncRepository);

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> call(
    NoParams params,
  ) async {
    // Directly call the repository method without decryption
    return await syncRepository.downloadAccounts();
  }
}
