import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';

void main() {
  test('BLoC event/state không đưa recovery key vào transition string', () {
    const recoveryCode = 'HA1-TEST_ONLY_RECOVERY_KEY';
    final values = <Object>[
      const RecoverEncryptedSync(recoveryCode),
      const SyncRecoveryKeyReady(recoveryCode),
      const SyncRecoveryKeyRotationReady(recoveryCode),
    ];

    for (final value in values) {
      expect(value.toString(), isNot(contains(recoveryCode)));
      expect(value.toString(), contains('[REDACTED]'));
    }
  });
}
