import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';

const _parsedAccount = ParsedTotpAccount(
  issuer: ' TEST_ONLY Issuer ',
  accountName: ' user@example.invalid ',
  secretKey: 'jbsw y3dp-ehpk3pxp',
  algorithm: 'sha256',
  digits: 8,
  period: 45,
);

void main() {
  test(
    'use case validate/normalize toàn batch trước repository call',
    () async {
      final repository = _ImportRepository();
      final result = await ImportAccounts(repository)(
        ImportAccountsParams(const [_parsedAccount]),
      );

      expect(
        result,
        const Right(AccountImportSummary(importedCount: 1, duplicateCount: 0)),
      );
      expect(repository.imported, hasLength(1));
      expect(
        repository.imported.single,
        const AuthenticatorAccount(
          id: '',
          issuer: 'TEST_ONLY Issuer',
          accountName: 'user@example.invalid',
          secretKey: 'JBSWY3DPEHPK3PXP',
          algorithm: 'SHA256',
          digits: 8,
          period: 45,
        ),
      );
    },
  );

  test('một record lỗi làm toàn batch fail trước persistence', () async {
    final repository = _ImportRepository();
    final result = await ImportAccounts(repository)(
      ImportAccountsParams(const [
        _parsedAccount,
        ParsedTotpAccount(
          issuer: 'TEST_ONLY Invalid',
          accountName: 'invalid@example.invalid',
          secretKey: 'NOT-BASE32-1',
          algorithm: 'SHA1',
          digits: 6,
          period: 30,
        ),
      ]),
    );

    expect(
      result,
      isA<Left<Failure, AccountImportSummary>>().having(
        (left) => left.value,
        'failure',
        isA<ValidationFailure>(),
      ),
    );
    expect(repository.importCalls, 0);
  });

  test('BLoC success chỉ mang count và reload sau import', () async {
    final repository = _ImportRepository();
    final bloc = AccountsBloc(
      getAccounts: GetAccounts(repository),
      addAccount: AddAccount(repository),
      deleteAccount: DeleteAccount(repository),
      updateAccount: UpdateAccount(repository),
      importAccounts: ImportAccounts(repository),
    );
    addTearDown(bloc.close);

    final success = bloc.stream.firstWhere(
      (state) => state is AccountImportSuccess,
    );
    final loaded = bloc.stream.firstWhere((state) => state is AccountsLoaded);
    final event = ImportAccountsRequested(const [_parsedAccount]);
    expect(event.toString(), contains('[1 REDACTED]'));
    expect(event.toString(), isNot(contains('JBSWY3')));

    bloc.add(event);

    expect(
      await success,
      const AccountImportSuccess(importedCount: 1, duplicateCount: 0),
    );
    expect(await loaded, isA<AccountsLoaded>());
  });

  test('BLoC không đưa lỗi storage của import ra presentation state', () async {
    final repository = _ImportRepository()
      ..importFailure = const StorageFailure(
        'TEST_ONLY SecureStorageException payload=internal',
      );
    final bloc = AccountsBloc(
      getAccounts: GetAccounts(repository),
      addAccount: AddAccount(repository),
      deleteAccount: DeleteAccount(repository),
      updateAccount: UpdateAccount(repository),
      importAccounts: ImportAccounts(repository),
    );
    addTearDown(bloc.close);

    bloc.add(ImportAccountsRequested(const [_parsedAccount]));
    final state =
        await bloc.stream.firstWhere((state) => state is AccountsError)
            as AccountsError;

    expect(state.message, isNot(contains('TEST_ONLY')));
    expect(state.message, isNot(contains('SecureStorageException')));
    expect(
      state.message,
      'Không thể nhập các mã đã chọn. Dữ liệu hiện có vẫn được giữ nguyên.',
    );
  });
}

class _ImportRepository implements AuthenticatorRepository {
  final List<AuthenticatorAccount> imported = [];
  int importCalls = 0;
  Failure? importFailure;

  @override
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) async {
    importCalls++;
    if (importFailure case final failure?) return Left(failure);
    imported
      ..clear()
      ..addAll(accounts);
    return Right(
      AccountImportSummary(importedCount: accounts.length, duplicateCount: 0),
    );
  }

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List<AuthenticatorAccount>.unmodifiable(imported));

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
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> accounts,
  ) async => throw UnimplementedError();
}
