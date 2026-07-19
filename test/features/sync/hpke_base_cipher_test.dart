import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/domain/services/hpke_base_cipher.dart';

void main() {
  group('HpkeBaseCipher', () {
    test('khớp RFC 9180 A.1.1 vector đầu tiên', () async {
      final cipher = HpkeBaseCipher(aead: HpkeAead.aes128Gcm);
      final ephemeralKeyPair = await X25519().newKeyPairFromSeed(
        _hex(
          '52c4a758a802cd8b936eceea314432798d5baf2d7e9235dc084ab1b9cfa2f736',
        ),
      );

      final sealed = await cipher.sealWithEphemeralKeyPair(
        recipientPublicKey: _hex(
          '3948cfe0ad1ddb695d780e59077195da6c56506b027329794ab02bca80815c4d',
        ),
        plaintext: _hex(
          '4265617574792069732074727574682c20747275746820626561757479',
        ),
        info: _hex('4f6465206f6e2061204772656369616e2055726e'),
        aad: _hex('436f756e742d30'),
        ephemeralKeyPair: ephemeralKeyPair,
      );

      expect(
        _encodeHex(sealed.encapsulatedKey),
        '37fda3567bdbd628e88668c3c8d7e97d1d1253b6d4ea6d44c150f741f1bf4431',
      );
      expect(
        _encodeHex(<int>[...sealed.ciphertext, ...sealed.authTag]),
        'f938558b5d72f1a23810b4be2ab4f84331acc02fc97babc53a52ae8218a355a9'
        '6d8770ac83d07bea87e13c512a',
      );

      final opened = await cipher.open(
        recipientPrivateKey: _hex(
          '4612c550263fc8ad58375df3f557aac531d26850903e55a9f23f21d8534e8ac8',
        ),
        sealed: sealed,
        info: _hex('4f6465206f6e2061204772656369616e2055726e'),
        aad: _hex('436f756e742d30'),
      );
      expect(
        _encodeHex(opened),
        '4265617574792069732074727574682c20747275746820626561757479',
      );
    });

    test('khớp official X25519/HKDF-SHA256/AES-256-GCM vector', () async {
      final cipher = HpkeBaseCipher();
      final ephemeralKeyPair = await X25519().newKeyPairFromSeed(
        _hex(
          '179d4b53b6365c45b600c4163b61d95cbc2f4d9e36f1695558dce265ab8bab11',
        ),
      );

      final sealed = await cipher.sealWithEphemeralKeyPair(
        recipientPublicKey: _hex(
          '430f4b9859665145a6b1ba274024487bd66f03a2dd577d7753c68d7d7d00c00c',
        ),
        plaintext: _hex(
          '4265617574792069732074727574682c20747275746820626561757479',
        ),
        info: _hex('4f6465206f6e2061204772656369616e2055726e'),
        aad: _hex('436f756e742d30'),
        ephemeralKeyPair: ephemeralKeyPair,
      );

      expect(
        _encodeHex(sealed.encapsulatedKey),
        '6c93e09869df3402d7bf231bf540fadd35cd56be14f97178f0954db94b7fc256',
      );
      expect(
        _encodeHex(<int>[...sealed.ciphertext, ...sealed.authTag]),
        'e5d84cd531cfb583096e7cfa9641bd3079cf3a91cda813c52deb5f512be99319'
        '80a41de125a925cdad859d5b7a',
      );

      final opened = await cipher.open(
        recipientPrivateKey: _hex(
          '497b4502664cfea5d5af0b39934dac72242a74f8480451e1aee7d6a53320333d',
        ),
        sealed: sealed,
        info: _hex('4f6465206f6e2061204772656369616e2055726e'),
        aad: _hex('436f756e742d30'),
      );
      expect(
        _encodeHex(opened),
        '4265617574792069732074727574682c20747275746820626561757479',
      );
    });

    test('AES-256-GCM round-trip một device DEK', () async {
      final cipher = HpkeBaseCipher();
      final recipient = await X25519().newKeyPair();
      final recipientData = await recipient.extract();
      final publicKey = await recipient.extractPublicKey();
      final dataKey = List<int>.generate(32, (index) => index);
      final info = utf8.encode('TEST_ONLY_DEVICE_WRAP_INFO');
      final aad = utf8.encode('TEST_ONLY_DEVICE_WRAP_AAD');

      final sealed = await cipher.seal(
        recipientPublicKey: publicKey.bytes,
        plaintext: dataKey,
        info: info,
        aad: aad,
      );
      final opened = await cipher.open(
        recipientPrivateKey: recipientData.bytes,
        sealed: sealed,
        info: info,
        aad: aad,
      );

      expect(opened, dataKey);
      expect(sealed.encapsulatedKey, hasLength(32));
      expect(sealed.ciphertext, hasLength(32));
      expect(sealed.authTag, hasLength(16));
    });

    test('sai context, recipient hoặc auth tag đều fail closed', () async {
      final cipher = HpkeBaseCipher();
      final recipient = await X25519().newKeyPair();
      final recipientData = await recipient.extract();
      final publicKey = await recipient.extractPublicKey();
      final otherRecipient = await X25519().newKeyPair();
      final otherRecipientData = await otherRecipient.extract();
      final info = utf8.encode('TEST_ONLY_DEVICE_WRAP_INFO');
      final aad = utf8.encode('TEST_ONLY_DEVICE_WRAP_AAD');
      final sealed = await cipher.seal(
        recipientPublicKey: publicKey.bytes,
        plaintext: List<int>.filled(32, 7),
        info: info,
        aad: aad,
      );

      await expectLater(
        cipher.open(
          recipientPrivateKey: recipientData.bytes,
          sealed: sealed,
          info: utf8.encode('TEST_ONLY_OTHER_INFO'),
          aad: aad,
        ),
        throwsA(isA<HpkeException>()),
      );
      await expectLater(
        cipher.open(
          recipientPrivateKey: otherRecipientData.bytes,
          sealed: sealed,
          info: info,
          aad: aad,
        ),
        throwsA(isA<HpkeException>()),
      );
      final tamperedTag = List<int>.from(sealed.authTag)..[0] ^= 1;
      await expectLater(
        cipher.open(
          recipientPrivateKey: recipientData.bytes,
          sealed: HpkeCiphertext(
            encapsulatedKey: sealed.encapsulatedKey,
            ciphertext: sealed.ciphertext,
            authTag: tamperedTag,
          ),
          info: info,
          aad: aad,
        ),
        throwsA(isA<HpkeException>()),
      );
    });

    test('X25519 low-order public key fail closed', () async {
      final cipher = HpkeBaseCipher();
      await expectLater(
        cipher.seal(
          recipientPublicKey: List<int>.filled(32, 0),
          plaintext: List<int>.filled(32, 1),
          info: utf8.encode('TEST_ONLY_DEVICE_WRAP_INFO'),
          aad: utf8.encode('TEST_ONLY_DEVICE_WRAP_AAD'),
        ),
        throwsA(isA<HpkeException>()),
      );
    });
  });
}

List<int> _hex(String value) {
  if (value.length.isOdd) throw const FormatException('Hex length lỗi.');
  return List<int>.generate(
    value.length ~/ 2,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
  );
}

String _encodeHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
