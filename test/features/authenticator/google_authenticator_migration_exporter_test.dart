import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_parser.dart';

void main() {
  const accounts = [
    AuthenticatorAccount(
      id: 'a',
      issuer: 'TEST_ONLY Example',
      accountName: 'alice@example.invalid',
      secretKey: 'JBSWY3DPEHPK3PXP',
      algorithm: 'SHA1',
      digits: 6,
    ),
    AuthenticatorAccount(
      id: 'b',
      issuer: 'TEST_ONLY Labs',
      accountName: 'bob@example.invalid',
      secretKey: 'KRSXG5DSNFXGOIDB',
      algorithm: 'SHA256',
      digits: 8,
    ),
  ];

  test('round-trip migration v1 giữ đủ semantics Google biểu diễn được', () {
    final parts = GoogleAuthenticatorMigrationExporter.export(
      accounts,
      batchId: 123456,
    );
    final collector = GoogleAuthenticatorMigrationBatchCollector();

    expect(parts, hasLength(1));
    final progress = collector.add(
      GoogleAuthenticatorMigrationParser.parse(parts.single.uri),
    );

    expect(progress.isComplete, isTrue);
    expect(progress.accounts, hasLength(2));
    expect(progress.accounts!.first.issuer, accounts.first.issuer);
    expect(progress.accounts!.first.accountName, accounts.first.accountName);
    expect(progress.accounts!.first.secretKey, accounts.first.secretKey);
    expect(progress.accounts!.first.algorithm, 'SHA1');
    expect(progress.accounts!.first.digits, 6);
    expect(progress.accounts!.last.algorithm, 'SHA256');
    expect(progress.accounts!.last.digits, 8);
    expect(parts.single.toString(), contains('uri: [REDACTED]'));
    expect(parts.single.toString(), isNot(contains(accounts.first.secretKey)));
  });

  test('tự chia multi-part bounded và collector ghép lại đúng thứ tự', () {
    final longAccounts = [
      for (var index = 0; index < 4; index++)
        AuthenticatorAccount(
          id: '$index',
          issuer: 'TEST_ONLY ${'I' * 300}',
          accountName: 'user-$index-${'N' * 300}@example.invalid',
          secretKey: 'JBSWY3DPEHPK3PXP',
        ),
    ];
    final parts = GoogleAuthenticatorMigrationExporter.export(
      longAccounts,
      batchId: 789,
    );
    final collector = GoogleAuthenticatorMigrationBatchCollector();

    expect(parts.length, greaterThan(1));
    expect(parts.every((part) => part.uri.length <= 1800), isTrue);
    GoogleAuthenticatorMigrationBatchProgress? progress;
    for (final part in parts.reversed) {
      progress = collector.add(
        GoogleAuthenticatorMigrationParser.parse(part.uri),
      );
    }
    expect(progress!.isComplete, isTrue);
    expect(
      progress.accounts!.map((account) => account.accountName),
      longAccounts.map((account) => account.accountName),
    );
  });

  test('fail closed khi Google format không giữ được period hoặc digits', () {
    expect(
      () => GoogleAuthenticatorMigrationExporter.export([
        const AuthenticatorAccount(
          id: 'period',
          issuer: 'TEST_ONLY',
          accountName: 'period@example.invalid',
          secretKey: 'JBSWY3DPEHPK3PXP',
          period: 60,
        ),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('30 giây'),
        ),
      ),
    );
    expect(
      () => GoogleAuthenticatorMigrationExporter.export([
        const AuthenticatorAccount(
          id: 'digits',
          issuer: 'TEST_ONLY',
          accountName: 'digits@example.invalid',
          secretKey: 'JBSWY3DPEHPK3PXP',
          digits: 7,
        ),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('6 hoặc 8'),
        ),
      ),
    );
  });
}
