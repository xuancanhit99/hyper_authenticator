import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/account_payload_validator.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';

void main() {
  test(
    'cloud validation preserves valid padded legacy and Unicode boundary',
    () {
      final padded = _account(
        issuer: '😀' * 256,
        accountName: '😀' * 512,
        secret: 'MZXW6YTBOI======',
      );
      expect(
        () => AccountPayloadValidator.validateCloudAccount(padded),
        returnsNormally,
      );
      expect(padded.secretKey, 'MZXW6YTBOI======');
      for (final secret in [
        'A',
        'A' * 1032,
        'JBSWY3DPEHPK3PXQ=',
        'jbswy3dpehpk3pxp',
      ]) {
        expect(
          () => AccountPayloadValidator.validateCloudAccount(
            _account(secret: secret),
          ),
          throwsFormatException,
        );
      }
    },
  );

  final invalid = <String, AuthenticatorAccount>{
    'issuer over 256 code points': _account(issuer: '😀' * 257),
    'account name over 512 code points': _account(accountName: '😀' * 513),
    'secret under 16 symbols after canonical padding': _account(secret: 'MY'),
    'secret over 1024 symbols': _account(secret: 'A' * 1032),
    'issuer contains NUL': _account(issuer: 'Test\u0000Issuer'),
    'account name contains NUL': _account(accountName: 'Test\u0000Account'),
    'issuer contains unpaired surrogate': _account(issuer: 'Test\uD800Issuer'),
    'account name contains unpaired surrogate': _account(
      accountName: 'Test\uDC00Account',
    ),
  };
  for (final entry in invalid.entries) {
    test('add/update/import reject ${entry.key} before writing', () async {
      final repository = _RecordingRepository();
      final account = entry.value;
      final add = await AddAccount(repository)(
        AddAccountParams(
          issuer: account.issuer,
          accountName: account.accountName,
          secretKey: account.secretKey,
          algorithm: account.algorithm,
          digits: account.digits,
          period: account.period,
        ),
      );
      final update = await UpdateAccount(repository)(
        UpdateAccountParams(account: account),
      );
      final imported = await ImportAccounts(repository)(
        ImportAccountsParams([
          const ParsedTotpAccount(
            issuer: 'TEST_ONLY valid',
            accountName: 'test@example.invalid',
            secretKey: 'JBSWY3DPEHPK3PXP',
            algorithm: 'SHA1',
            digits: 6,
            period: 30,
          ),
          ParsedTotpAccount(
            issuer: account.issuer,
            accountName: account.accountName,
            secretKey: account.secretKey,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
          ),
        ]),
      );
      for (final result in [add, update, imported]) {
        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<ValidationFailure>()),
          (_) {},
        );
      }
      expect(repository.writes, 0);
    });
  }

  test(
    'editing padded legacy key does not change key bytes or break RPC bounds',
    () async {
      final repository = _RecordingRepository();
      final legacy = _account(issuer: 'Renamed', secret: 'GEZDGNBVGY3TQ===');
      final result = await UpdateAccount(repository)(
        UpdateAccountParams(account: legacy),
      );
      expect(result.isRight(), isTrue);
      expect(repository.last?.secretKey, legacy.secretKey);
      expect(repository.last?.issuer, 'Renamed');
      expect(
        AccountPayloadValidator.normalizeSecretForStorage('MZXW6YTBOI'),
        'MZXW6YTBOI======',
      );
    },
  );

  test(
    'all admission paths accept Unicode SQL boundaries without truncation',
    () async {
      final repository = _RecordingRepository();
      final account = _account(
        issuer: '😀' * 256,
        accountName: '😀' * 512,
        secret: 'A' * 1024,
      );
      final added = await AddAccount(repository)(
        AddAccountParams(
          issuer: account.issuer,
          accountName: account.accountName,
          secretKey: account.secretKey,
          algorithm: account.algorithm,
          digits: account.digits,
          period: account.period,
        ),
      );
      final updated = await UpdateAccount(repository)(
        UpdateAccountParams(account: account),
      );
      final imported = await ImportAccounts(repository)(
        ImportAccountsParams([
          ParsedTotpAccount(
            issuer: account.issuer,
            accountName: account.accountName,
            secretKey: account.secretKey,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
          ),
        ]),
      );
      expect(added.isRight(), isTrue);
      expect(updated.isRight(), isTrue);
      expect(imported.isRight(), isTrue);
      expect(repository.writes, 3);
      expect(repository.last?.issuer, account.issuer);
      expect(repository.last?.accountName, account.accountName);
      expect(repository.last?.secretKey, account.secretKey);
    },
  );
}

AuthenticatorAccount _account({
  String issuer = 'TEST_ONLY issuer',
  String accountName = 'test@example.invalid',
  String secret = 'JBSWY3DPEHPK3PXP',
}) => AuthenticatorAccount(
  id: '11111111-1111-4111-8111-111111111111',
  issuer: issuer,
  accountName: accountName,
  secretKey: secret,
);

class _RecordingRepository implements AuthenticatorRepository {
  int writes = 0;
  AuthenticatorAccount? last;

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) async {
    writes++;
    last = AuthenticatorAccount(
      id: 'new-id',
      issuer: issuer,
      accountName: accountName,
      secretKey: secretKey,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
    return Right(last!);
  }

  @override
  Future<Either<Failure, Unit>> updateAccount(
    AuthenticatorAccount account,
  ) async {
    writes++;
    last = account;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) async {
    writes++;
    last = accounts.last;
    return Right(
      AccountImportSummary(importedCount: accounts.length, duplicateCount: 0),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
