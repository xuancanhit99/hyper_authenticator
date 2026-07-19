import 'package:cryptography/cryptography.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_installation_identity_store.dart';
import 'package:hyper_authenticator/features/settings/domain/repositories/authenticator_device_session_repository.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_store.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/device_key_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/services/device_key_cipher.dart';
import 'package:injectable/injectable.dart';

abstract class DeviceKeyCoordinator {
  Future<Either<Failure, ActiveDeviceKeyAuthorization>> ensureCurrentDevice({
    required String userId,
    required List<int> dataKeyBytes,
    required int keyGeneration,
  });

  Future<Either<Failure, DeviceKeyRotationPlan>> prepareRotation({
    required String userId,
    required List<int> currentDataKeyBytes,
    required List<int> nextDataKeyBytes,
    required int currentKeyGeneration,
  });
}

@LazySingleton(as: DeviceKeyCoordinator)
class DeviceKeyEnrollmentUseCase implements DeviceKeyCoordinator {
  final AuthenticatorInstallationIdentityStore _identityStore;
  final AuthenticatorDeviceSessionRepository _sessionRepository;
  final DeviceKeyMaterialStore _keyStore;
  final DeviceKeyRepository _deviceKeyRepository;
  final DeviceKeyCipher _cipher;

  DeviceKeyEnrollmentUseCase(
    this._identityStore,
    this._sessionRepository,
    this._keyStore,
    this._deviceKeyRepository,
    this._cipher,
  );

  @override
  Future<Either<Failure, ActiveDeviceKeyAuthorization>> ensureCurrentDevice({
    required String userId,
    required List<int> dataKeyBytes,
    required int keyGeneration,
  }) async {
    try {
      if (userId.trim().isEmpty ||
          dataKeyBytes.length != 32 ||
          keyGeneration < 1) {
        return const Left(
          SyncOperationFailure('Device key enrollment context không hợp lệ.'),
        );
      }
      final identity = await _identityStore.readOrCreate();
      _value(await _sessionRepository.load(userId: userId));
      final material = await _keyStore.getOrCreate(
        userId: userId,
        installationId: identity.installationId,
      );
      final enrollment = _value(
        await _deviceKeyRepository.beginEnrollment(
          userId: userId,
          installationId: identity.installationId,
          publicKeyBytes: material.publicKeyBytes,
          bindingSecretBytes: material.bindingSecretBytes,
        ),
      );
      if (enrollment.keyGeneration != keyGeneration) {
        throw const _DeviceKeyFailure(
          SyncRevisionConflictFailure(
            'Key generation đã thay đổi trong lúc enroll thiết bị.',
          ),
        );
      }

      var current = _currentKey(
        _value(await _deviceKeyRepository.list(userId: userId)),
        expectedDeviceKeyId: enrollment.deviceKeyId,
        expectedInstallationId: identity.installationId,
        expectedPublicKey: material.publicKeyBytes,
      );
      if (current.state == AuthenticatorDeviceKeyState.pending) {
        final wrappedKey = await _cipher.wrapDataKey(
          dataKeyBytes: dataKeyBytes,
          recipientPublicKeyBytes: current.publicKeyBytes,
          userId: userId,
          installationId: current.installationId,
          deviceKeyId: current.deviceKeyId,
          keyGeneration: keyGeneration,
        );
        final proof = await _cipher.createMembershipProof(
          dataKeyBytes: dataKeyBytes,
          publicKeyBytes: current.publicKeyBytes,
          userId: userId,
          installationId: current.installationId,
          deviceKeyId: current.deviceKeyId,
          keyGeneration: keyGeneration,
        );
        final verifier = await _cipher.createVaultMembershipVerifier(
          dataKeyBytes: dataKeyBytes,
          userId: userId,
          keyGeneration: keyGeneration,
        );
        _value(
          await _deviceKeyRepository.publishWrap(
            userId: userId,
            targetDeviceKeyId: current.deviceKeyId,
            bindingSecretBytes: material.bindingSecretBytes,
            wrappedKey: wrappedKey,
            vaultMembershipVerifier: verifier,
            membershipProof: proof,
          ),
        );
        current = _currentKey(
          _value(await _deviceKeyRepository.list(userId: userId)),
          expectedDeviceKeyId: enrollment.deviceKeyId,
          expectedInstallationId: identity.installationId,
          expectedPublicKey: material.publicKeyBytes,
        );
      }

      await _verifyCurrentWrap(
        current: current,
        material: material,
        dataKeyBytes: dataKeyBytes,
        userId: userId,
        keyGeneration: keyGeneration,
      );
      if (current.state == AuthenticatorDeviceKeyState.wrapped) {
        _value(
          await _deviceKeyRepository.confirmCurrent(
            userId: userId,
            deviceKeyId: current.deviceKeyId,
            bindingSecretBytes: material.bindingSecretBytes,
            keyGeneration: keyGeneration,
          ),
        );
        current = _currentKey(
          _value(await _deviceKeyRepository.list(userId: userId)),
          expectedDeviceKeyId: enrollment.deviceKeyId,
          expectedInstallationId: identity.installationId,
          expectedPublicKey: material.publicKeyBytes,
        );
      }
      if (current.state != AuthenticatorDeviceKeyState.active) {
        throw const _DeviceKeyFailure(
          SyncOperationFailure('Device key chưa được server kích hoạt.'),
        );
      }
      await _verifyCurrentWrap(
        current: current,
        material: material,
        dataKeyBytes: dataKeyBytes,
        userId: userId,
        keyGeneration: keyGeneration,
      );
      return Right(
        ActiveDeviceKeyAuthorization(
          deviceKey: current,
          bindingSecretBytes: material.bindingSecretBytes,
        ),
      );
    } on _DeviceKeyFailure catch (error) {
      return Left(error.failure);
    } on DeviceKeyStoreException {
      return const Left(
        StorageFailure('Không thể đọc hoặc lưu device private key an toàn.'),
      );
    } on DeviceKeyCryptoException catch (error) {
      return Left(SyncOperationFailure(error.message));
    } catch (_) {
      return const Left(
        SyncOperationFailure('Device key enrollment thất bại an toàn.'),
      );
    }
  }

  @override
  Future<Either<Failure, DeviceKeyRotationPlan>> prepareRotation({
    required String userId,
    required List<int> currentDataKeyBytes,
    required List<int> nextDataKeyBytes,
    required int currentKeyGeneration,
  }) async {
    final authorization = await ensureCurrentDevice(
      userId: userId,
      dataKeyBytes: currentDataKeyBytes,
      keyGeneration: currentKeyGeneration,
    );
    return authorization.fold(Left.new, (activeAuthorization) async {
      try {
        final keys = _value(await _deviceKeyRepository.list(userId: userId));
        final activeKeys = keys
            .where((key) => key.state == AuthenticatorDeviceKeyState.active)
            .toList(growable: false);
        if (activeKeys.isEmpty || activeKeys.length > 32) {
          throw const _DeviceKeyFailure(
            SyncOperationFailure('Tập active device không hợp lệ để rotate.'),
          );
        }
        final nextGeneration = currentKeyGeneration + 1;
        final nextVerifier = await _cipher.createVaultMembershipVerifier(
          dataKeyBytes: nextDataKeyBytes,
          userId: userId,
          keyGeneration: nextGeneration,
        );
        final wraps = <DeviceKeyRotationWrap>[];
        for (final key in activeKeys) {
          final wrappedKey = await _cipher.wrapDataKey(
            dataKeyBytes: nextDataKeyBytes,
            recipientPublicKeyBytes: key.publicKeyBytes,
            userId: userId,
            installationId: key.installationId,
            deviceKeyId: key.deviceKeyId,
            keyGeneration: nextGeneration,
          );
          final proof = await _cipher.createMembershipProof(
            dataKeyBytes: nextDataKeyBytes,
            publicKeyBytes: key.publicKeyBytes,
            userId: userId,
            installationId: key.installationId,
            deviceKeyId: key.deviceKeyId,
            keyGeneration: nextGeneration,
          );
          wraps.add(
            DeviceKeyRotationWrap(
              deviceKeyId: key.deviceKeyId,
              wrappedVaultKey: wrappedKey,
              membershipProof: proof,
            ),
          );
        }
        return Right(
          DeviceKeyRotationPlan(
            bindingSecretBytes: activeAuthorization.bindingSecretBytes,
            nextVaultMembershipVerifier: nextVerifier,
            wraps: wraps,
          ),
        );
      } on _DeviceKeyFailure catch (error) {
        return Left(error.failure);
      } on DeviceKeyCryptoException catch (error) {
        return Left(SyncOperationFailure(error.message));
      } catch (_) {
        return const Left(
          SyncOperationFailure('Không thể chuẩn bị exact device wrap set.'),
        );
      }
    });
  }

  AuthenticatorDeviceKey _currentKey(
    List<AuthenticatorDeviceKey> keys, {
    required String expectedDeviceKeyId,
    required String expectedInstallationId,
    required List<int> expectedPublicKey,
  }) {
    final current = keys.where((key) => key.isCurrent).toList(growable: false);
    if (current.length != 1 ||
        current.single.deviceKeyId != expectedDeviceKeyId ||
        current.single.installationId != expectedInstallationId ||
        Mac(current.single.publicKeyBytes) != Mac(expectedPublicKey)) {
      throw const _DeviceKeyFailure(
        SyncOperationFailure(
          'Server trả device key không khớp cài đặt hiện tại.',
        ),
      );
    }
    return current.single;
  }

  Future<void> _verifyCurrentWrap({
    required AuthenticatorDeviceKey current,
    required DeviceKeyMaterial material,
    required List<int> dataKeyBytes,
    required String userId,
    required int keyGeneration,
  }) async {
    final wrappedKey = current.wrappedVaultKey;
    final proof = current.membershipProof;
    if (wrappedKey == null ||
        proof == null ||
        wrappedKey.keyGeneration != keyGeneration) {
      throw const _DeviceKeyFailure(
        SyncOperationFailure('Device wrap hiện tại không đầy đủ hoặc đã cũ.'),
      );
    }
    final unwrapped = await _cipher.unwrapDataKey(
      wrappedKey: wrappedKey,
      recipientPrivateKeyBytes: material.privateKeyBytes,
      recipientPublicKeyBytes: material.publicKeyBytes,
      userId: userId,
      installationId: current.installationId,
      deviceKeyId: current.deviceKeyId,
    );
    final proofValid = await _cipher.verifyMembershipProof(
      proof: proof,
      dataKeyBytes: unwrapped,
      publicKeyBytes: current.publicKeyBytes,
      userId: userId,
      installationId: current.installationId,
      deviceKeyId: current.deviceKeyId,
      keyGeneration: keyGeneration,
    );
    if (Mac(unwrapped) != Mac(dataKeyBytes) || !proofValid) {
      throw const _DeviceKeyFailure(
        SyncOperationFailure(
          'Device wrap không chứng minh quyền sở hữu vault key hiện tại.',
        ),
      );
    }
  }

  T _value<T>(Either<Failure, T> result) => result.fold(
    (failure) => throw _DeviceKeyFailure(failure),
    (value) => value,
  );
}

class _DeviceKeyFailure implements Exception {
  final Failure failure;

  const _DeviceKeyFailure(this.failure);
}
