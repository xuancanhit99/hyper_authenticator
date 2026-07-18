import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/data/datasources/authenticator_local_data_source.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';

const _allowHistoricalVaultMutation = bool.fromEnvironment(
  'ALLOW_LINUX_HISTORICAL_VAULT_MUTATION',
);
const _testAccount = AuthenticatorAccount(
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
    'bản 1.0.0+9 ghi vault bằng Linux storage plugin lịch sử',
    (tester) async {
      expect(
        _allowHistoricalVaultMutation,
        isTrue,
        reason: 'Chỉ chạy qua Linux historical-upgrade harness có opt-in.',
      );

      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      final dataSource = AuthenticatorLocalDataSourceImpl(
        secureStorage: storage,
        uuid: const Uuid(),
      );
      await dataSource.saveAccount(_testAccount);

      final accounts = await dataSource.getAccounts();
      expect(accounts, [_testAccount]);
      debugPrint('LINUX_HISTORICAL_PHASE=legacy-vault-seeded');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
