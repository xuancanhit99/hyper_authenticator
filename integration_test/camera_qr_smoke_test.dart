import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowVaultReset = bool.fromEnvironment('ALLOW_DEVICE_TEST_VAULT_RESET');
const _testIssuer = 'TEST_ONLY Camera';
const _testAccountName = 'camera-acceptance@example.invalid';
const _testSecret = 'JBSWY3DPEHPK3PXP';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'camera quét standard otpauth rồi import qua preview',
    (tester) async {
      expect(
        _allowVaultReset,
        isTrue,
        reason: 'Chỉ chạy trên clean Android AVD với camera fixture.',
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
        final accountsBloc = di.sl<AccountsBloc>();
        await _replaceVault(repository, const []);
        accountsBloc.add(LoadAccounts());
        await _pumpUntil(tester, find.text('Chưa có mã xác thực'));

        await tester.tap(find.byTooltip('Thêm tài khoản'));
        await _pumpUntil(tester, find.byKey(AddAccountPage.issuerFieldKey));
        await tester.tap(find.byTooltip('Quét mã QR'));

        await _pumpUntil(
          tester,
          find.text('Import tài khoản'),
          timeout: const Duration(minutes: 2),
        );
        expect(find.text(_testIssuer), findsOneWidget);
        expect(find.text(_testAccountName), findsOneWidget);
        expect(find.textContaining(_testSecret), findsNothing);
        await tester.tap(find.widgetWithText(FilledButton, 'Import'));
        await _pumpUntil(tester, find.text(_testIssuer));

        final accounts = await _readVault(repository);
        expect(accounts, hasLength(1));
        expect(accounts.single.issuer, _testIssuer);
        expect(accounts.single.accountName, _testAccountName);
        expect(accounts.single.secretKey, _testSecret);
        expect(accounts.single.algorithm, 'SHA1');
        expect(accounts.single.digits, 6);
        expect(accounts.single.period, 30);
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
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
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
  await tester.pump(const Duration(milliseconds: 300));
}
