import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowVaultReset = bool.fromEnvironment('ALLOW_DEVICE_TEST_VAULT_RESET');
const _testIssuer = 'TEST_ONLY Device Vault';
const _testAccountName = 'device-smoke@example.invalid';
const _testSecret = 'JBSWY3DPEHPK3PXP';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'local vault round-trip qua UI, lifecycle và navigation',
    (tester) async {
      _phase('start');
      expect(
        _allowVaultReset,
        isTrue,
        reason:
            'Test này xóa local vault trên target. Chỉ chạy qua device harness có opt-in rõ ràng.',
      );

      final preferences = await SharedPreferences.getInstance();
      FlutterSecureStorage? secureStorage;
      AuthenticatorRepository? repository;

      try {
        await preferences.setBool('biometric_enabled', false);

        await app.main();
        await _pumpUntil(tester, find.byTooltip('Thêm tài khoản'));
        _phase('bootstrap-ready');

        secureStorage = di.sl<FlutterSecureStorage>();
        await _verifySecureStorageProbe(secureStorage);
        _phase('secure-storage-probe-verified');

        repository = di.sl<AuthenticatorRepository>();
        final accountsBloc = di.sl<AccountsBloc>();
        await _replaceVault(repository, const []);
        accountsBloc.add(LoadAccounts());
        await _pumpUntil(
          tester,
          find.text('Không tìm thấy tài khoản phù hợp.'),
        );
        _phase('empty-vault-ready');

        await tester.tap(find.byTooltip('Thêm tài khoản'));
        await _pumpUntil(tester, find.byKey(AddAccountPage.issuerFieldKey));

        await tester.enterText(
          find.byKey(AddAccountPage.issuerFieldKey),
          _testIssuer,
        );
        await tester.enterText(
          find.byKey(AddAccountPage.accountNameFieldKey),
          _testAccountName,
        );
        await tester.enterText(
          find.byKey(AddAccountPage.secretFieldKey),
          _testSecret,
        );
        await tester.tap(find.byKey(AddAccountPage.submitButtonKey));
        await _pumpUntil(tester, find.text(_testIssuer));
        _phase('account-added');

        final persisted = await _readVault(repository);
        expect(persisted, hasLength(1));
        expect(persisted.single.issuer, _testIssuer);
        expect(persisted.single.accountName, _testAccountName);
        expect(persisted.single.secretKey, _testSecret);
        expect(persisted.single.algorithm, 'SHA1');
        expect(persisted.single.digits, 6);
        expect(persisted.single.period, 30);
        _phase('storage-round-trip-verified');

        _phase('lifecycle-transition-start');
        await _transitionLifecycle(tester, const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]);
        await _pumpUntil(tester, find.text(_testIssuer));
        _phase('lifecycle-transition-complete');

        accountsBloc.add(LoadAccounts());
        await _pumpUntil(tester, find.text(_testAccountName));
        _phase('bloc-reload-complete');

        await tester.tap(find.byKey(MainNavigationPage.settingsTabKey).last);
        await _pumpUntil(tester, find.text('Cài đặt'));
        _phase('settings-navigation-complete');
        await tester.tap(find.byKey(MainNavigationPage.accountsTabKey).last);
        await _pumpUntil(tester, find.text(_testIssuer));
        _phase('accounts-navigation-complete');

        await _replaceVault(repository, const []);
        accountsBloc.add(LoadAccounts());
        await _pumpUntil(
          tester,
          find.text('Không tìm thấy tài khoản phù hợp.'),
        );
        expect(await _readVault(repository), isEmpty);
        _phase('cleanup-verified');
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

Future<void> _verifySecureStorageProbe(FlutterSecureStorage storage) async {
  const key = 'TEST_ONLY:local-vault-smoke:probe';
  const value = 'TEST_ONLY_OK';
  try {
    await storage.write(key: key, value: value);
    expect(await storage.read(key: key), value);
    expect((await storage.readAll())[key], value);
    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull);
  } catch (error) {
    final errorCode = switch (error) {
      PlatformException(:final code, :final message, :final details) =>
        'PlatformException:$code:${message ?? 'no-message'}:'
            '${details is int ? details : 'no-status'}',
      _ => error.runtimeType.toString(),
    };
    throw TestFailure('Secure-storage preflight thất bại ($errorCode).');
  } finally {
    try {
      await storage.delete(key: key);
    } catch (_) {
      // Destructive harness trap xóa exact test service nếu plugin cleanup fail.
    }
  }
}

void _phase(String name) {
  debugPrint('DEVICE_INTEGRATION_PHASE=$name');
}

Future<void> _transitionLifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump(const Duration(milliseconds: 100));
  }
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
  await tester.pump(const Duration(milliseconds: 200));
}
