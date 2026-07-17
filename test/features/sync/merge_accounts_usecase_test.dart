import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/merge_accounts_usecase.dart';

const _testSecret = 'JBSWY3DPEHPK3PXP';

AuthenticatorAccount _account({
  required String id,
  String issuer = 'Example',
  String accountName = 'user@example.invalid',
  String secretKey = _testSecret,
}) {
  return AuthenticatorAccount(
    id: id,
    issuer: issuer,
    accountName: accountName,
    secretKey: secretKey,
    algorithm: 'SHA1',
    digits: 6,
    period: 30,
  );
}

void main() {
  test('merge dùng stable ID và cho phép hai account cùng label', () async {
    final repository = _InMemoryAuthenticatorRepository([
      _account(id: '11111111-1111-4111-8111-111111111111'),
    ]);
    final remote = _account(id: '22222222-2222-4222-8222-222222222222');

    final result = await MergeAccountsUseCase(repository)([remote]);

    result.fold((failure) => fail(failure.message), (accounts) {
      expect(accounts, hasLength(2));
      expect(accounts.map((account) => account.id), contains(remote.id));
      expect(repository.savedIds, [remote.id]);
    });
  });

  test('record local thắng compatibility merge khi trùng stable ID', () async {
    final local = _account(
      id: '11111111-1111-4111-8111-111111111111',
      issuer: 'Local',
    );
    final repository = _InMemoryAuthenticatorRepository([local]);
    final remote = _account(id: local.id, issuer: 'Remote');

    final result = await MergeAccountsUseCase(repository)([remote]);

    result.fold((failure) => fail(failure.message), (accounts) {
      expect(accounts.single.issuer, 'Local');
      expect(repository.savedIds, isEmpty);
    });
  });

  test('remote record không hợp lệ dừng merge trước persistence', () async {
    final repository = _InMemoryAuthenticatorRepository(const []);
    final remote = _account(
      id: '11111111-1111-4111-8111-111111111111',
      secretKey: 'not-base32!',
    );

    final result = await MergeAccountsUseCase(repository)([remote]);

    expect(result.isLeft(), isTrue);
    expect(repository.savedIds, isEmpty);
  });
}

class _InMemoryAuthenticatorRepository implements AuthenticatorRepository {
  final List<AuthenticatorAccount> accounts;
  final List<String> savedIds = [];

  _InMemoryAuthenticatorRepository(List<AuthenticatorAccount> accounts)
    : accounts = [...accounts];

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right([...accounts]);

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) async {
    accounts.add(account);
    savedIds.add(account.id);
    return Right(account);
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async => throw UnimplementedError();
}
