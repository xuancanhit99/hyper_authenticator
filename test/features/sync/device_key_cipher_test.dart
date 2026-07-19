import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:hyper_authenticator/features/sync/domain/services/device_key_cipher.dart';

void main() {
  group('DeviceKeyCipher', () {
    late DeviceKeyCipher cipher;
    late DeviceKeyMaterial device;

    setUp(() async {
      cipher = DeviceKeyCipher();
      device = await cipher.createKeyMaterial();
    });

    test('tạo key material X25519 và binding secret 256-bit', () async {
      expect(device.privateKeyBytes, hasLength(32));
      expect(device.publicKeyBytes, hasLength(32));
      expect(device.bindingSecretBytes, hasLength(32));
      expect(
        await cipher.publicKeyForPrivateKey(device.privateKeyBytes),
        device.publicKeyBytes,
      );
      expect(device.toString(), isNot(contains(device.privateKeyBytes.first)));
      expect(device.toString(), contains('<redacted>'));
    });

    test('wrap và unwrap DEK bind user/device/generation', () async {
      final dataKey = List<int>.generate(32, (index) => 255 - index);
      final wrapped = await cipher.wrapDataKey(
        dataKeyBytes: dataKey,
        recipientPublicKeyBytes: device.publicKeyBytes,
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
        deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        keyGeneration: 4,
      );

      expect(wrapped.formatVersion, 1);
      expect(wrapped.keyGeneration, 4);
      expect(wrapped.kem, DeviceWrappedVaultKey.kemName);
      expect(wrapped.kdf, DeviceWrappedVaultKey.kdfName);
      expect(wrapped.aead, DeviceWrappedVaultKey.aeadName);
      expect(wrapped.toString(), isNot(contains(wrapped.ciphertext)));
      expect(
        await cipher.unwrapDataKey(
          wrappedKey: wrapped,
          recipientPrivateKeyBytes: device.privateKeyBytes,
          recipientPublicKeyBytes: device.publicKeyBytes,
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
          deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        ),
        dataKey,
      );

      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: wrapped,
          recipientPrivateKeyBytes: device.privateKeyBytes,
          recipientPublicKeyBytes: device.publicKeyBytes,
          userId: 'TEST_ONLY_USER_B',
          installationId: 'TEST_ONLY_INSTALLATION_A',
          deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        ),
        throwsA(isA<DeviceKeyCryptoException>()),
      );
      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: DeviceWrappedVaultKey(
            formatVersion: wrapped.formatVersion,
            keyGeneration: wrapped.keyGeneration + 1,
            kem: wrapped.kem,
            kdf: wrapped.kdf,
            aead: wrapped.aead,
            encapsulatedKey: wrapped.encapsulatedKey,
            ciphertext: wrapped.ciphertext,
            authTag: wrapped.authTag,
          ),
          recipientPrivateKeyBytes: device.privateKeyBytes,
          recipientPublicKeyBytes: device.publicKeyBytes,
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
          deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        ),
        throwsA(isA<DeviceKeyCryptoException>()),
      );
    });

    test('device-wrapped envelope round-trip và future shape fail closed', () {
      const envelope = DeviceWrappedVaultKey(
        formatVersion: 1,
        keyGeneration: 3,
        kem: DeviceWrappedVaultKey.kemName,
        kdf: DeviceWrappedVaultKey.kdfName,
        aead: DeviceWrappedVaultKey.aeadName,
        encapsulatedKey: 'TEST_ONLY_ENCAPSULATED_KEY',
        ciphertext: 'TEST_ONLY_CIPHERTEXT',
        authTag: 'TEST_ONLY_AUTH_TAG',
      );

      expect(DeviceWrappedVaultKey.fromJson(envelope.toJson()), envelope);
      expect(
        () => DeviceWrappedVaultKey.fromJson(<String, dynamic>{
          ...envelope.toJson(),
          'key_generation': 0,
        }),
        throwsFormatException,
      );
      expect(envelope.toString(), isNot(contains(envelope.ciphertext)));
    });

    test(
      'membership proof chỉ hợp lệ với current DEK và exact identity',
      () async {
        final dataKey = List<int>.generate(32, (index) => index + 1);
        final proof = await cipher.createMembershipProof(
          dataKeyBytes: dataKey,
          publicKeyBytes: device.publicKeyBytes,
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
          deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
          keyGeneration: 2,
        );

        expect(
          await cipher.verifyMembershipProof(
            proof: proof,
            dataKeyBytes: dataKey,
            publicKeyBytes: device.publicKeyBytes,
            userId: 'TEST_ONLY_USER_A',
            installationId: 'TEST_ONLY_INSTALLATION_A',
            deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
            keyGeneration: 2,
          ),
          isTrue,
        );
        expect(
          await cipher.verifyMembershipProof(
            proof: proof,
            dataKeyBytes: List<int>.filled(32, 9),
            publicKeyBytes: device.publicKeyBytes,
            userId: 'TEST_ONLY_USER_A',
            installationId: 'TEST_ONLY_INSTALLATION_A',
            deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
            keyGeneration: 2,
          ),
          isFalse,
        );
        expect(
          await cipher.verifyMembershipProof(
            proof: proof,
            dataKeyBytes: dataKey,
            publicKeyBytes: device.publicKeyBytes,
            userId: 'TEST_ONLY_USER_A',
            installationId: 'TEST_ONLY_INSTALLATION_B',
            deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
            keyGeneration: 2,
          ),
          isFalse,
        );
      },
    );

    test('private key khác và envelope tamper fail closed', () async {
      final other = await cipher.createKeyMaterial();
      final wrapped = await cipher.wrapDataKey(
        dataKeyBytes: List<int>.filled(32, 3),
        recipientPublicKeyBytes: device.publicKeyBytes,
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
        deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        keyGeneration: 1,
      );

      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: wrapped,
          recipientPrivateKeyBytes: other.privateKeyBytes,
          recipientPublicKeyBytes: device.publicKeyBytes,
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
          deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        ),
        throwsA(isA<DeviceKeyCryptoException>()),
      );

      final tag = base64Url.decode(wrapped.authTag)..[0] ^= 1;
      await expectLater(
        cipher.unwrapDataKey(
          wrappedKey: DeviceWrappedVaultKey(
            formatVersion: wrapped.formatVersion,
            keyGeneration: wrapped.keyGeneration,
            kem: wrapped.kem,
            kdf: wrapped.kdf,
            aead: wrapped.aead,
            encapsulatedKey: wrapped.encapsulatedKey,
            ciphertext: wrapped.ciphertext,
            authTag: base64UrlEncode(tag),
          ),
          recipientPrivateKeyBytes: device.privateKeyBytes,
          recipientPublicKeyBytes: device.publicKeyBytes,
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
          deviceKeyId: 'TEST_ONLY_DEVICE_KEY_A',
        ),
        throwsA(isA<DeviceKeyCryptoException>()),
      );
    });
  });
}
