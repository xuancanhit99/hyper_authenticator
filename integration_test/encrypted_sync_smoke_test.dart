import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_installation_identity_store.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_device_session_remote_data_source.dart';
import 'package:hyper_authenticator/features/settings/data/repositories/authenticator_device_session_repository_impl.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_store.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/encrypted_vault_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/data/repositories/device_key_repository_impl.dart';
import 'package:hyper_authenticator/features/sync/data/repositories/encrypted_vault_repository_impl.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/encrypted_sync_metadata_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/device_key_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/vault_key_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/services/device_key_cipher.dart';
import 'package:hyper_authenticator/features/sync/domain/services/vault_cipher.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/device_key_enrollment_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/encrypted_vault_sync_usecase.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _allowRemoteMutation = bool.fromEnvironment(
  'ALLOW_E2EE_REMOTE_TEST_MUTATION',
);
const _testEmail = String.fromEnvironment('E2EE_TEST_EMAIL');
const _testPassword = String.fromEnvironment('E2EE_TEST_PASSWORD');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);
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
      final installationIdentity = di
          .sl<AuthenticatorInstallationIdentityStore>();
      final deviceKeyStore = di.sl<DeviceKeyMaterialStore>();
      String? userId;
      String? primaryInstallationId;
      SupabaseClient? secondaryClient;
      DeviceKeyEnrollmentUseCase? secondaryCoordinator;

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
        final primaryIdentity = await installationIdentity.readOrCreate();
        primaryInstallationId = primaryIdentity.installationId;
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

        final generationOneDataKey = _right(
          await keyRepository.read(userId),
          'read-generation-one-data-key',
        );
        expect(generationOneDataKey, isNotNull);
        final activeSecondaryClient = SupabaseClient(
          _supabaseUrl,
          _supabasePublishableKey,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        secondaryClient = activeSecondaryClient;
        final secondaryAuth = await activeSecondaryClient.auth
            .signInWithPassword(email: _testEmail, password: _testPassword);
        expect(secondaryAuth.user?.id, userId);
        final secondaryInstallationId = const Uuid().v4();
        expect(
          await preferences.setString(
            AuthenticatorInstallationIdentityStore.preferenceKey,
            secondaryInstallationId,
          ),
          isTrue,
        );
        final secondaryCipher = DeviceKeyCipher();
        final secondaryMaterial = await secondaryCipher.createKeyMaterial();
        secondaryCoordinator = DeviceKeyEnrollmentUseCase(
          installationIdentity,
          AuthenticatorDeviceSessionRepositoryImpl(
            AuthenticatorDeviceSessionRemoteDataSource(activeSecondaryClient),
            installationIdentity,
          ),
          _IntegrationDeviceKeyStore(secondaryMaterial),
          DeviceKeyRepositoryImpl(
            DeviceKeyRemoteDataSource(activeSecondaryClient),
          ),
          secondaryCipher,
        );
        _right(
          await secondaryCoordinator.ensureCurrentDevice(
            userId: userId,
            dataKeyBytes: generationOneDataKey!,
            keyGeneration: 1,
          ),
          'enroll-secondary-session-device-key',
        );
        expect(
          await preferences.setString(
            AuthenticatorInstallationIdentityStore.preferenceKey,
            primaryInstallationId,
          ),
          isTrue,
        );
        final deviceKeys = _right(
          await di.sl<DeviceKeyRepository>().list(userId: userId),
          'list-two-active-device-keys',
        );
        expect(
          deviceKeys
              .where((key) => key.state == AuthenticatorDeviceKeyState.active)
              .length,
          2,
        );
        _phase('two-independent-sessions-active-generation-1');

        _right(await keyRepository.delete(userId), 'drop-device-key-v1');
        final identity = await installationIdentity.readOrCreate();
        await deviceKeyStore.delete(
          userId: userId,
          installationId: identity.installationId,
        );
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
        _phase('lost-device-key-ha1-recovery-revision-2');

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
        final storedPreRotationDataKey = _right(
          await keyRepository.read(userId),
          'read-pre-rotation-device-key',
        );
        expect(storedPreRotationDataKey, isNotNull);
        final preRotationDataKey = storedPreRotationDataKey!;
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

        expect(secondaryCoordinator, isNotNull);
        final activeSecondaryCoordinator = secondaryCoordinator;
        expect(
          await preferences.setString(
            AuthenticatorInstallationIdentityStore.preferenceKey,
            secondaryInstallationId,
          ),
          isTrue,
        );
        final secondaryKeys = _IntegrationVaultKeyRepository()
          ..values[userId] = List<int>.from(preRotationDataKey);
        final secondaryMetadata = _IntegrationMetadataRepository()
          ..revisions[userId] = 3
          ..enabled[userId] = true;
        final secondarySync = EncryptedVaultSyncUseCase(
          _IntegrationAuthRepository(UserEntity(id: userId)),
          _IntegrationAuthenticatorRepository(const [
            _initialAccount,
            _secondAccount,
          ]),
          EncryptedVaultRepositoryImpl(
            EncryptedVaultRemoteDataSource(activeSecondaryClient),
          ),
          secondaryKeys,
          secondaryMetadata,
          VaultCipher(),
          activeSecondaryCoordinator,
        );
        final secondaryReady = _right(
          await secondarySync.inspect(),
          'secondary-session-auto-unwrap',
        );
        expect(secondaryReady, isA<EncryptedSyncReady>());
        expect((secondaryReady as EncryptedSyncReady).revision, 4);
        expect(
          secondaryKeys.values[userId],
          isNot(orderedEquals(preRotationDataKey)),
        );
        _phase('secondary-session-auto-unwrapped-generation-2');
        expect(
          await preferences.setString(
            AuthenticatorInstallationIdentityStore.preferenceKey,
            primaryInstallationId,
          ),
          isTrue,
        );

        _right(
          await keyRepository.write(userId, preRotationDataKey),
          'restore-stale-device-key',
        );
        final autoUnwrapped = _right(
          await sync.inspect(),
          'auto-unwrap-current-device-key',
        );
        expect(autoUnwrapped, isA<EncryptedSyncReady>());
        expect((autoUnwrapped as EncryptedSyncReady).revision, 4);
        final refreshedDataKey = _right(
          await keyRepository.read(userId),
          'read-auto-unwrapped-device-key',
        );
        expect(refreshedDataKey, isNotNull);
        expect(refreshedDataKey, isNot(orderedEquals(preRotationDataKey)));
        _phase('stale-dek-auto-unwrapped-revision-4');

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
        if (primaryInstallationId != null) {
          await preferences.setString(
            AuthenticatorInstallationIdentityStore.preferenceKey,
            primaryInstallationId,
          );
        }
        if (secondaryClient != null) {
          await secondaryClient.auth.signOut(scope: SignOutScope.local);
          await secondaryClient.dispose();
        }
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

class _IntegrationDeviceKeyStore implements DeviceKeyMaterialStore {
  final DeviceKeyMaterial material;

  _IntegrationDeviceKeyStore(this.material);

  @override
  Future<DeviceKeyMaterial> getOrCreate({
    required String userId,
    required String installationId,
  }) async => material;

  @override
  Future<DeviceKeyMaterial?> read({
    required String userId,
    required String installationId,
  }) async => material;

  @override
  Future<void> delete({
    required String userId,
    required String installationId,
  }) async {}
}

class _IntegrationVaultKeyRepository implements VaultKeyRepository {
  final Map<String, List<int>> values = <String, List<int>>{};

  @override
  Future<Either<Failure, List<int>?>> read(String userId) async =>
      Right(values[userId]);

  @override
  Future<Either<Failure, Unit>> write(
    String userId,
    List<int> dataKeyBytes,
  ) async {
    values[userId] = List<int>.unmodifiable(dataKeyBytes);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(String userId) async {
    values.remove(userId);
    return const Right(unit);
  }
}

class _IntegrationMetadataRepository
    implements EncryptedSyncMetadataRepository {
  final Map<String, int> revisions = <String, int>{};
  final Map<String, bool> enabled = <String, bool>{};

  @override
  int? readLastRevision(String userId) => revisions[userId];

  @override
  Future<void> writeLastRevision(String userId, int revision) async {
    revisions[userId] = revision;
  }

  @override
  bool readEnabled(String userId) => enabled[userId] ?? false;

  @override
  Future<void> writeEnabled(String userId, bool value) async {
    enabled[userId] = value;
  }
}

class _IntegrationAuthenticatorRepository implements AuthenticatorRepository {
  final List<AuthenticatorAccount> accounts;

  _IntegrationAuthenticatorRepository(List<AuthenticatorAccount> initial)
    : accounts = List<AuthenticatorAccount>.from(initial);

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List<AuthenticatorAccount>.unmodifiable(accounts));

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> replacement,
  ) async {
    accounts
      ..clear()
      ..addAll(replacement);
    return const Right(unit);
  }

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
}

class _IntegrationAuthRepository implements AuthRepository {
  final UserEntity user;

  _IntegrationAuthRepository(this.user);

  @override
  UserEntity? get currentUserEntity => user;

  @override
  Stream<UserEntity?> get authEntityChanges => Stream<UserEntity?>.value(user);

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(user);

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name,
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> revokeOtherSessions() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> signOut() async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      throw UnimplementedError();
}
