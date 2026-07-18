import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';

const _allowHistoricalVaultMutation = bool.fromEnvironment(
  'ALLOW_LINUX_HISTORICAL_VAULT_MUTATION',
);
const _expectedAccount = AuthenticatorAccount(
  id: '00000000-0000-4000-8000-000000000009',
  issuer: 'TEST_ONLY Historical Linux',
  accountName: 'historical-upgrade@example.invalid',
  secretKey: 'JBSWY3DPEHPK3PXP',
  algorithm: 'SHA256',
  digits: 8,
  period: 45,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bản hiện tại đọc và nâng cấp Linux vault thật từ 1.0.0+9',
    (tester) async {
      expect(
        _allowHistoricalVaultMutation,
        isTrue,
        reason: 'Chỉ chạy qua Linux historical-upgrade harness có opt-in.',
      );

      await app.main();
      await _pumpUntil(tester, find.text(_expectedAccount.issuer));
      debugPrint('LINUX_HISTORICAL_PHASE=current-app-visible');

      final repository = di.sl<AuthenticatorRepository>();
      final result = await repository.getAccounts();
      final accounts = result.fold(
        (failure) => throw TestFailure(
          'Không đọc được historical vault (${failure.runtimeType}).',
        ),
        (value) => value,
      );
      expect(accounts, [_expectedAccount]);

      final storage = di.sl<FlutterSecureStorage>();
      final storedValues = await storage.readAll();
      expect(
        storedValues.keys.any((key) => key.startsWith('ha:v2:commit:')),
        isTrue,
        reason: 'Historical logical record phải được publish sang COW v2.',
      );
      debugPrint('LINUX_HISTORICAL_PHASE=v2-migration-verified');

      await storage.deleteAll();
      expect(await storage.readAll(), isEmpty);
      debugPrint('LINUX_HISTORICAL_PHASE=cleanup-verified');
    },
    timeout: const Timeout(Duration(minutes: 5)),
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
      throw TestFailure('Timeout khi chờ historical account xuất hiện.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}
