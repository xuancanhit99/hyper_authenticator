import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/sync_repository.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class UploadAccountsUseCase implements UseCase<Unit, UploadAccountsParams> {
  final SyncRepository syncRepository;

  UploadAccountsUseCase(this.syncRepository);

  @override
  Future<Either<Failure, Unit>> call(UploadAccountsParams params) async {
    // Directly call the repository method without encryption
    return await syncRepository.uploadAccounts(params.accounts);
  }
}

class UploadAccountsParams {
  final List<AuthenticatorAccount> accounts;

  UploadAccountsParams({required this.accounts});
}
