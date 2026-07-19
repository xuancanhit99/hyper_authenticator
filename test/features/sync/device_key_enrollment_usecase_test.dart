import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_installation_identity_store.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:hyper_authenticator/features/settings/domain/repositories/authenticator_device_session_repository.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_store.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/device_key_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/services/device_key_cipher.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/device_key_enrollment_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = '33333333-3333-4333-8333-333333333333';
  const installationId = '11111111-1111-4111-8111-111111111111';
  const deviceKeyId = '22222222-2222-4222-8222-222222222222';
  late DeviceKeyCipher cipher;
  late DeviceKeyMaterial material;
  late _MemoryDeviceKeyRepository remote;
  late DeviceKeyEnrollmentUseCase useCase;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AuthenticatorInstallationIdentityStore.preferenceKey: installationId,
    });
    cipher = DeviceKeyCipher();
    material = await cipher.createKeyMaterial();
    remote = _MemoryDeviceKeyRepository(
      deviceKeyId: deviceKeyId,
      installationId: installationId,
      publicKey: material.publicKeyBytes,
    );
    useCase = DeviceKeyEnrollmentUseCase(
      AuthenticatorInstallationIdentityStore(
        await SharedPreferences.getInstance(),
        const Uuid(),
      ),
      _SessionRepository(),
      _MaterialStore(material),
      remote,
      cipher,
    );
  });

  test(
    'pending self-wrap được verify local trước khi confirm active',
    () async {
      final dataKey = List<int>.generate(32, (index) => index + 1);

      final result = await useCase.ensureCurrentDevice(
        userId: userId,
        dataKeyBytes: dataKey,
        keyGeneration: 1,
      );

      final current = result.fold(
        (failure) => throw TestFailure(failure.message),
        (value) => value,
      );
      expect(current.deviceKey.state, AuthenticatorDeviceKeyState.active);
      expect(current.bindingSecretBytes, material.bindingSecretBytes);
      expect(current.toString(), contains('<redacted>'));
      expect(remote.publishCount, 1);
      expect(remote.confirmCount, 1);
      expect(remote.listCount, 3);
    },
  );

  test('membership proof bị sửa không được confirm', () async {
    remote.tamperProofAfterPublish = true;

    final result = await useCase.ensureCurrentDevice(
      userId: userId,
      dataKeyBytes: List<int>.filled(32, 7),
      keyGeneration: 1,
    );

    expect(result.fold((failure) => failure, (_) => null), isA<Failure>());
    expect(remote.publishCount, 1);
    expect(remote.confirmCount, 0);
    expect(remote.state, AuthenticatorDeviceKeyState.wrapped);
  });

  test('generation đổi giữa snapshot và enrollment fail closed', () async {
    remote.keyGeneration = 2;

    final result = await useCase.ensureCurrentDevice(
      userId: userId,
      dataKeyBytes: List<int>.filled(32, 8),
      keyGeneration: 1,
    );

    expect(
      result.fold((failure) => failure, (_) => null),
      isA<SyncRevisionConflictFailure>(),
    );
    expect(remote.publishCount, 0);
    expect(remote.confirmCount, 0);
  });

  test(
    'rotation plan wrap next DEK cho exact active device generation',
    () async {
      final currentDataKey = List<int>.filled(32, 8);
      final nextDataKey = List<int>.filled(32, 9);
      final enrolled = await useCase.ensureCurrentDevice(
        userId: userId,
        dataKeyBytes: currentDataKey,
        keyGeneration: 1,
      );
      expect(enrolled.isRight(), isTrue);

      final result = await useCase.prepareRotation(
        userId: userId,
        currentDataKeyBytes: currentDataKey,
        nextDataKeyBytes: nextDataKey,
        currentKeyGeneration: 1,
      );
      final plan = result.fold(
        (failure) => throw TestFailure(failure.message),
        (value) => value,
      );

      expect(plan.wraps, hasLength(1));
      expect(plan.wraps.single.deviceKeyId, deviceKeyId);
      expect(plan.wraps.single.wrappedVaultKey.keyGeneration, 2);
      expect(plan.toString(), contains('<redacted>'));
      expect(
        await cipher.unwrapDataKey(
          wrappedKey: plan.wraps.single.wrappedVaultKey,
          recipientPrivateKeyBytes: material.privateKeyBytes,
          recipientPublicKeyBytes: material.publicKeyBytes,
          userId: userId,
          installationId: installationId,
          deviceKeyId: deviceKeyId,
        ),
        nextDataKey,
      );
    },
  );
}

class _MaterialStore implements DeviceKeyMaterialStore {
  final DeviceKeyMaterial material;

  _MaterialStore(this.material);

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

class _SessionRepository implements AuthenticatorDeviceSessionRepository {
  @override
  Future<Either<Failure, List<AuthenticatorDeviceSession>>> load({
    required String userId,
  }) async => const Right(<AuthenticatorDeviceSession>[]);

  @override
  Future<Either<Failure, void>> revoke({
    required String userId,
    required String registrationId,
  }) async => const Right(null);
}

class _MemoryDeviceKeyRepository implements DeviceKeyRepository {
  final String deviceKeyId;
  final String installationId;
  final List<int> publicKey;
  int keyGeneration = 1;
  AuthenticatorDeviceKeyState state = AuthenticatorDeviceKeyState.pending;
  DeviceWrappedVaultKey? wrappedKey;
  String? proof;
  bool tamperProofAfterPublish = false;
  int publishCount = 0;
  int confirmCount = 0;
  int listCount = 0;

  _MemoryDeviceKeyRepository({
    required this.deviceKeyId,
    required this.installationId,
    required this.publicKey,
  });

  @override
  Future<Either<Failure, DeviceKeyEnrollment>> beginEnrollment({
    required String userId,
    required String installationId,
    required List<int> publicKeyBytes,
    required List<int> bindingSecretBytes,
    required String vaultMembershipVerifier,
  }) async => Right(
    DeviceKeyEnrollment(
      deviceKeyId: deviceKeyId,
      state: state,
      keyGeneration: keyGeneration,
    ),
  );

  @override
  Future<Either<Failure, List<AuthenticatorDeviceKey>>> list({
    required String userId,
  }) async {
    listCount++;
    return Right(<AuthenticatorDeviceKey>[
      AuthenticatorDeviceKey(
        deviceKeyId: deviceKeyId,
        installationId: installationId,
        publicKeyBytes: publicKey,
        state: state,
        createdAt: DateTime.utc(2026, 7, 19),
        wrappedAt: state == AuthenticatorDeviceKeyState.pending
            ? null
            : DateTime.utc(2026, 7, 19, 0, 1),
        activatedAt: state == AuthenticatorDeviceKeyState.active
            ? DateTime.utc(2026, 7, 19, 0, 2)
            : null,
        isCurrent: true,
        wrappedVaultKey: wrappedKey,
        membershipProof: proof,
      ),
    ]);
  }

  @override
  Future<Either<Failure, void>> publishWrap({
    required String userId,
    required String targetDeviceKeyId,
    required List<int> bindingSecretBytes,
    required DeviceWrappedVaultKey wrappedKey,
    required String vaultMembershipVerifier,
    required String membershipProof,
  }) async {
    publishCount++;
    this.wrappedKey = wrappedKey;
    proof = tamperProofAfterPublish
        ? base64UrlEncode(List<int>.filled(32, 99))
        : membershipProof;
    state = AuthenticatorDeviceKeyState.wrapped;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> confirmCurrent({
    required String userId,
    required String deviceKeyId,
    required List<int> bindingSecretBytes,
    required int keyGeneration,
  }) async {
    confirmCount++;
    state = AuthenticatorDeviceKeyState.active;
    return const Right(null);
  }
}
