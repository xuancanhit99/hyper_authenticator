import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/vault_key_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/encrypted_vault_sync_usecase.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowRemoteMutation = bool.fromEnvironment(
  'ALLOW_E2EE_REMOTE_TEST_MUTATION',
);
const _testEmail = String.fromEnvironment('E2EE_TEST_EMAIL');
const _testPassword = String.fromEnvironment('E2EE_TEST_PASSWORD');
const _testSecret = 'JBSWY3DPEHPK3PXP';

const _initialAccount = AuthenticatorAccount(
  id: 'e2ee-linux-account-1',
  issuer: 'TEST_ONLY E2EE Linux',
  accountName: 'primary@example.invalid',
  secretKey: _testSecret,
  algorithm: 'SHA256',
  digits: 8,
  period: 45,
);

const _secondAccount = AuthenticatorAccount(
  id: 'e2ee-linux-account-2',
  issuer: 'TEST_ONLY E2EE Linux',
  accountName: 'secondary@example.invalid',
  secretKey: _testSecret,
  algorithm: 'SHA512',
  digits: 7,
  period: 60,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'authenticated E2EE setup, sync, recovery và key rotation',
    (tester) async {
      _phase('start');
      expect(
        _allowRemoteMutation,
        isTrue,
        reason:
            'Remote E2EE smoke chỉ được chạy qua harness tạo isolated test user.',
      );
      expect(_testEmail, isNotEmpty);
      expect(_testPassword, isNotEmpty);

      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('biometric_enabled', false);
      await app.main();
      await tester.pump(const Duration(milliseconds: 500));

      final authRepository = di.sl<AuthRepository>();
      final localRepository = di.sl<AuthenticatorRepository>();
      final keyRepository = di.sl<VaultKeyRepository>();
      final sync = di.sl<EncryptedVaultSyncUseCase>();
      String? userId;

      try {
        final user = _right(
          await authRepository.signInWithPassword(
            email: _testEmail,
            password: _testPassword,
          ),
          'sign-in',
        );
        userId = user.id;
        expect(userId, isNotEmpty);
        _phase('authenticated');

        _right(await localRepository.replaceAccounts(const []), 'reset-vault');
        _right(
          await localRepository.replaceAccounts(const [_initialAccount]),
          'seed-local-vault',
        );

        expect(
          _right(await sync.inspect(), 'inspect-empty-cloud'),
          isA<EncryptedSyncSetupRequired>(),
        );
        final setup = _right(await sync.prepareSetup(), 'prepare-setup');
        expect(setup, isA<EncryptedSyncRecoveryKeyReady>());
        final recoveryKeyV1 =
            (setup as EncryptedSyncRecoveryKeyReady).recoveryCode;
        expect(recoveryKeyV1, isNotEmpty);
        final setupCompleted = _right(
          await sync.confirmSetup(),
          'confirm-setup',
        );
        _expectRevision(setupCompleted, 1);
        _phase('setup-revision-1');

        _right(
          await localRepository.replaceAccounts(const [
            _initialAccount,
            _secondAccount,
          ]),
          'mutate-local-vault',
        );
        _expectRevision(_right(await sync.sync(), 'sync-local-change'), 2);
        _phase('sync-revision-2');

        _right(await keyRepository.delete(userId), 'drop-device-key-v1');
        _right(
          await localRepository.replaceAccounts(const []),
          'clear-device-vault-v1',
        );
        expect(
          _right(await sync.inspect(), 'inspect-fresh-device-v1'),
          isA<EncryptedSyncRecoveryRequired>(),
        );
        _expectRevision(
          _right(await sync.recover(recoveryKeyV1), 'recover-v1'),
          2,
        );
        await _expectVault(localRepository, 2);
        _phase('fresh-device-recovery-revision-2');

        final recoveryRotation = _right(
          await sync.prepareRecoveryKeyRotation(),
          'prepare-recovery-key-rotation',
        );
        expect(recoveryRotation, isA<EncryptedSyncRecoveryKeyRotationReady>());
        final recoveryKeyV2 =
            (recoveryRotation as EncryptedSyncRecoveryKeyRotationReady)
                .recoveryCode;
        expect(recoveryKeyV2, isNotEmpty);
        _expectRevision(
          _right(
            await sync.confirmRecoveryKeyRotation(),
            'confirm-recovery-key-rotation',
          ),
          3,
        );
        _phase('recovery-key-rotation-revision-3');

        _right(await keyRepository.delete(userId), 'drop-device-key-v2');
        _right(
          await localRepository.replaceAccounts(const []),
          'clear-device-vault-v2',
        );
        _left(await sync.recover(recoveryKeyV1), 'reject-old-recovery-key');
        await _expectVault(localRepository, 0);
        _expectRevision(
          _right(await sync.recover(recoveryKeyV2), 'recover-v2'),
          3,
        );
        await _expectVault(localRepository, 2);
        _phase('old-recovery-key-rejected');

        final vaultRotation = _right(
          await sync.prepareVaultKeyRotation(),
          'prepare-vault-key-rotation',
        );
        expect(vaultRotation, isA<EncryptedSyncVaultKeyRotationReady>());
        final recoveryKeyV3 =
            (vaultRotation as EncryptedSyncVaultKeyRotationReady).recoveryCode;
        expect(recoveryKeyV3, isNotEmpty);
        _expectRevision(
          _right(
            await sync.confirmVaultKeyRotation(),
            'confirm-vault-key-rotation',
          ),
          4,
        );
        _phase('vault-key-rotation-revision-4');

        _right(await keyRepository.delete(userId), 'drop-device-key-v3');
        _right(
          await localRepository.replaceAccounts(const []),
          'clear-device-vault-v3',
        );
        _left(
          await sync.recover(recoveryKeyV2),
          'reject-pre-vault-rotation-key',
        );
        await _expectVault(localRepository, 0);
        _expectRevision(
          _right(await sync.recover(recoveryKeyV3), 'recover-v3'),
          4,
        );
        await _expectVault(localRepository, 2);
        final ready = _right(await sync.inspect(), 'inspect-ready');
        expect(ready, isA<EncryptedSyncReady>());
        expect((ready as EncryptedSyncReady).revision, 4);
        expect(ready.isEnabled, isTrue);
        _phase('final-recovery-and-inspect-ready');
      } finally {
        sync.cancelSensitiveOperation();
        if (userId != null && userId.isNotEmpty) {
          _right(await keyRepository.delete(userId), 'cleanup-device-key');
        }
        _right(
          await localRepository.replaceAccounts(const []),
          'cleanup-local-vault',
        );
        _right(await authRepository.signOut(), 'cleanup-sign-out');
        _phase('client-cleanup-complete');
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

T _right<T>(Either<Failure, T> result, String phase) => result.fold(
  (failure) => throw TestFailure('$phase thất bại (${failure.runtimeType}).'),
  (value) => value,
);

Failure _left<T>(Either<Failure, T> result, String phase) => result.fold(
  (failure) => failure,
  (_) => throw TestFailure('$phase đã thành công ngoài dự kiến.'),
);

void _expectRevision(EncryptedSyncResult result, int revision) {
  expect(result, isA<EncryptedSyncCompleted>());
  expect((result as EncryptedSyncCompleted).revision, revision);
}

Future<void> _expectVault(
  AuthenticatorRepository repository,
  int expectedLength,
) async {
  final accounts = _right(await repository.getAccounts(), 'read-local-vault');
  expect(accounts, hasLength(expectedLength));
  if (expectedLength == 2) {
    final byId = {for (final account in accounts) account.id: account};
    expect(
      byId.keys,
      containsAll(<String>[_initialAccount.id, _secondAccount.id]),
    );
    expect(byId[_initialAccount.id]?.algorithm, 'SHA256');
    expect(byId[_initialAccount.id]?.digits, 8);
    expect(byId[_initialAccount.id]?.period, 45);
    expect(byId[_secondAccount.id]?.algorithm, 'SHA512');
    expect(byId[_secondAccount.id]?.digits, 7);
    expect(byId[_secondAccount.id]?.period, 60);
  }
}

void _phase(String name) {
  // Không log credential, recovery key, TOTP secret hoặc encrypted payload.
  // Chỉ phase name cố định được phép xuất hiện trong CI evidence.
  // ignore: avoid_print
  print('E2EE_INTEGRATION_PHASE=$name');
}
