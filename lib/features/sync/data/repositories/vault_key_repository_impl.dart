import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/vault_key_store.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/vault_key_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: VaultKeyRepository)
class VaultKeyRepositoryImpl implements VaultKeyRepository {
  final VaultKeyStore _store;

  VaultKeyRepositoryImpl(this._store);

  @override
  Future<Either<Failure, List<int>?>> read(String userId) async {
    try {
      return Right(await _store.readDataKey(userId));
    } catch (_) {
      return const Left(StorageFailure('Không thể đọc vault key an toàn.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> write(
    String userId,
    List<int> dataKeyBytes,
  ) async {
    try {
      await _store.writeDataKey(userId, dataKeyBytes);
      return const Right(unit);
    } catch (_) {
      return const Left(StorageFailure('Không thể lưu vault key an toàn.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> delete(String userId) async {
    try {
      await _store.deleteDataKey(userId);
      return const Right(unit);
    } catch (_) {
      return const Left(StorageFailure('Không thể xóa vault key cũ.'));
    }
  }
}
