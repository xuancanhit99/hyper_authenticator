import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowVaultReset = bool.fromEnvironment('ALLOW_DEVICE_TEST_VAULT_RESET');
const _testSecret = 'JBSWY3DPEHPK3PXP';

const _standardAccount = AuthenticatorAccount(
  id: '00000000-0000-4000-8000-000000000201',
  issuer: 'TEST_ONLY Chuẩn:Unicode',
  accountName: 'người-dùng:acceptance@example.invalid',
  secretKey: _testSecret,
  algorithm: 'SHA512',
  digits: 8,
  period: 45,
);

const _googleAccounts = <AuthenticatorAccount>[
  AuthenticatorAccount(
    id: '00000000-0000-4000-8000-000000000202',
    issuer: 'TEST_ONLY Google One',
    accountName: 'one@example.invalid',
    secretKey: _testSecret,
  ),
  AuthenticatorAccount(
    id: '00000000-0000-4000-8000-000000000203',
    issuer: 'TEST_ONLY Google Two',
    accountName: 'two@example.invalid',
    secretKey: _testSecret,
    algorithm: 'SHA256',
    digits: 8,
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'standard và Google migration round-trip qua secure local repository',
    (tester) async {
      _phase('start');
      expect(
        _allowVaultReset,
        isTrue,
        reason: 'Chỉ chạy trên clean emulator/simulator qua guarded harness.',
      );

      final preferences = await SharedPreferences.getInstance();
      FlutterSecureStorage? secureStorage;
      AuthenticatorRepository? repository;

      try {
        await preferences.setBool('biometric_enabled', false);
        await app.main();
        await _pumpUntil(tester, find.byTooltip('Thêm tài khoản'));

        secureStorage = di.sl<FlutterSecureStorage>();
        repository = di.sl<AuthenticatorRepository>();
        final importAccounts = di.sl<ImportAccounts>();
        await _replaceVault(repository, const []);
        _phase('clean-vault-ready');

        final standardParts = TotpUriExporter.export([_standardAccount]);
        expect(standardParts, hasLength(1));
        final standardParsed = TotpUriParser.parse(standardParts.single.uri);
        expect(standardParsed.issuer, _standardAccount.issuer);
        expect(standardParsed.accountName, _standardAccount.accountName);
        expect(standardParsed.secretKey, _standardAccount.secretKey);
        expect(standardParsed.algorithm, _standardAccount.algorithm);
        expect(standardParsed.digits, _standardAccount.digits);
        expect(standardParsed.period, _standardAccount.period);

        final standardImport = await importAccounts(
          ImportAccountsParams([standardParsed]),
        );
        final standardSummary = standardImport.fold(
          (failure) => throw TestFailure(
            'Standard import thất bại (${failure.runtimeType}).',
          ),
          (summary) => summary,
        );
        expect(standardSummary.importedCount, 1);
        expect(standardSummary.duplicateCount, 0);
        _expectSemantics(
          (await _readVault(repository)).single,
          _standardAccount,
        );

        final duplicateImport = await importAccounts(
          ImportAccountsParams([standardParsed]),
        );
        duplicateImport.fold(
          (failure) => throw TestFailure(
            'Duplicate import thất bại (${failure.runtimeType}).',
          ),
          (summary) {
            expect(summary.importedCount, 0);
            expect(summary.duplicateCount, 1);
          },
        );
        expect(await _readVault(repository), hasLength(1));
        _phase('standard-round-trip-and-dedupe-verified');

        await _replaceVault(repository, const []);
        final googleParts = GoogleAuthenticatorMigrationExporter.export(
          _googleAccounts,
          batchId: 20260730,
        );
        final collector = GoogleAuthenticatorMigrationBatchCollector();
        List<ParsedTotpAccount>? collected;
        for (final part in googleParts.reversed) {
          final progress = collector.add(
            GoogleAuthenticatorMigrationParser.parse(part.uri),
          );
          if (progress.isComplete) {
            collected = progress.accounts;
          }
        }
        expect(collected, isNotNull);
        expect(collected, hasLength(_googleAccounts.length));

        final googleImport = await importAccounts(
          ImportAccountsParams(collected!),
        );
        googleImport.fold(
          (failure) => throw TestFailure(
            'Google import thất bại (${failure.runtimeType}).',
          ),
          (summary) {
            expect(summary.importedCount, _googleAccounts.length);
            expect(summary.duplicateCount, 0);
          },
        );

        final persisted = await _readVault(repository);
        expect(persisted, hasLength(_googleAccounts.length));
        for (var index = 0; index < _googleAccounts.length; index++) {
          _expectSemantics(persisted[index], _googleAccounts[index]);
        }
        _phase('google-round-trip-verified');
      } finally {
        try {
          if (repository != null) {
            await _replaceVault(repository, const []);
          }
        } finally {
          try {
            await secureStorage?.deleteAll();
          } finally {
            await preferences.clear();
          }
        }
        _phase('finally-cleanup-complete');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

void _expectSemantics(
  AuthenticatorAccount actual,
  AuthenticatorAccount expected,
) {
  expect(actual.issuer, expected.issuer);
  expect(actual.accountName, expected.accountName);
  expect(actual.secretKey, expected.secretKey);
  expect(actual.algorithm, expected.algorithm);
  expect(actual.digits, expected.digits);
  expect(actual.period, expected.period);
}

Future<List<AuthenticatorAccount>> _readVault(
  AuthenticatorRepository repository,
) async {
  final result = await repository.getAccounts();
  return result.fold(
    (failure) => throw TestFailure(
      'Không đọc được test vault (${failure.runtimeType}).',
    ),
    (accounts) => accounts,
  );
}

Future<void> _replaceVault(
  AuthenticatorRepository repository,
  List<AuthenticatorAccount> accounts,
) async {
  final result = await repository.replaceAccounts(accounts);
  result.fold(
    (failure) => throw TestFailure(
      'Không reset được test vault (${failure.runtimeType}).',
    ),
    (_) {},
  );
}

void _phase(String name) {
  // Không log payload, URI, identity hoặc secret của fixture.
  printOnFailure('IMPORT_EXPORT_DEVICE_PHASE=$name');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timeout khi chờ widget: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}
