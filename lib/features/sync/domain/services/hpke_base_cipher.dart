import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class HpkeException implements Exception {
  final String message;

  const HpkeException(this.message);

  @override
  String toString() => 'HpkeException: $message';
}

class HpkeCiphertext {
  final List<int> encapsulatedKey;
  final List<int> ciphertext;
  final List<int> authTag;

  HpkeCiphertext({
    required List<int> encapsulatedKey,
    required List<int> ciphertext,
    required List<int> authTag,
  }) : encapsulatedKey = List<int>.unmodifiable(encapsulatedKey),
       ciphertext = List<int>.unmodifiable(ciphertext),
       authTag = List<int>.unmodifiable(authTag);

  @override
  String toString() => 'HpkeCiphertext(<redacted>)';
}

enum HpkeAead {
  aes128Gcm(identifier: 0x0001, keyLength: 16),
  aes256Gcm(identifier: 0x0002, keyLength: 32);

  final int identifier;
  final int keyLength;

  const HpkeAead({required this.identifier, required this.keyLength});
}

/// Minimal one-shot RFC 9180 Base-mode implementation.
///
/// The KEM and KDF are fixed to DHKEM(X25519, HKDF-SHA256) and HKDF-SHA256.
/// Only sequence number zero is exposed because each device DEK wrap creates a
/// fresh sender context and encrypts exactly one 32-byte value.
class HpkeBaseCipher {
  static const _kemId = 0x0020;
  static const _kdfId = 0x0001;
  static const _hashLength = 32;
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _modeBase = 0x00;
  static final _hpkeVersion = ascii.encode('HPKE-v1');
  static final _kemSuiteId = <int>[
    ...ascii.encode('KEM'),
    ..._i2osp(_kemId, 2),
  ];

  final HpkeAead aead;
  final X25519 _kem;
  final Hmac _hmac;
  final AesGcm _aead;

  HpkeBaseCipher({this.aead = HpkeAead.aes256Gcm})
    : _kem = X25519(),
      _hmac = Hmac.sha256(),
      _aead = aead == HpkeAead.aes128Gcm
          ? AesGcm.with128bits()
          : AesGcm.with256bits();

  Future<HpkeCiphertext> seal({
    required List<int> recipientPublicKey,
    required List<int> plaintext,
    required List<int> info,
    required List<int> aad,
  }) async {
    final ephemeralKeyPair = await _kem.newKeyPair();
    return sealWithEphemeralKeyPair(
      recipientPublicKey: recipientPublicKey,
      plaintext: plaintext,
      info: info,
      aad: aad,
      ephemeralKeyPair: ephemeralKeyPair,
    );
  }

  Future<HpkeCiphertext> sealWithEphemeralKeyPair({
    required List<int> recipientPublicKey,
    required List<int> plaintext,
    required List<int> info,
    required List<int> aad,
    required KeyPair ephemeralKeyPair,
  }) async {
    _requireLength(recipientPublicKey, 32, 'Recipient public key');
    try {
      final recipientKey = SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      );
      final encapsulatedKey = await ephemeralKeyPair.extractPublicKey();
      if (encapsulatedKey is! SimplePublicKey) {
        throw const HpkeException('Ephemeral public key không hợp lệ.');
      }
      final sharedSecret = await _encap(
        senderKeyPair: ephemeralKeyPair,
        recipientPublicKey: recipientKey,
        encapsulatedKey: encapsulatedKey.bytes,
      );
      final context = await _keySchedule(
        sharedSecret: sharedSecret,
        info: info,
      );
      final box = await _aead.encrypt(
        plaintext,
        secretKey: SecretKey(context.key),
        nonce: context.baseNonce,
        aad: aad,
      );
      return HpkeCiphertext(
        encapsulatedKey: encapsulatedKey.bytes,
        ciphertext: box.cipherText,
        authTag: box.mac.bytes,
      );
    } on HpkeException {
      rethrow;
    } catch (_) {
      throw const HpkeException('Không thể tạo HPKE ciphertext.');
    }
  }

  Future<List<int>> open({
    required List<int> recipientPrivateKey,
    required HpkeCiphertext sealed,
    required List<int> info,
    required List<int> aad,
  }) async {
    _requireLength(recipientPrivateKey, 32, 'Recipient private key');
    _requireLength(sealed.encapsulatedKey, 32, 'Encapsulated key');
    _requireLength(sealed.authTag, _tagLength, 'Authentication tag');
    try {
      final recipientKeyPair = await _kem.newKeyPairFromSeed(
        recipientPrivateKey,
      );
      final recipientPublicKey = await recipientKeyPair.extractPublicKey();
      final sharedSecret = await _decap(
        recipientKeyPair: recipientKeyPair,
        recipientPublicKey: recipientPublicKey.bytes,
        encapsulatedKey: sealed.encapsulatedKey,
      );
      final context = await _keySchedule(
        sharedSecret: sharedSecret,
        info: info,
      );
      final clearText = await _aead.decrypt(
        SecretBox(
          sealed.ciphertext,
          nonce: context.baseNonce,
          mac: Mac(sealed.authTag),
        ),
        secretKey: SecretKey(context.key),
        aad: aad,
      );
      return List<int>.unmodifiable(clearText);
    } on HpkeException {
      rethrow;
    } catch (_) {
      throw const HpkeException('Không thể mở HPKE ciphertext.');
    }
  }

  Future<List<int>> _encap({
    required KeyPair senderKeyPair,
    required SimplePublicKey recipientPublicKey,
    required List<int> encapsulatedKey,
  }) async {
    final dh = await _kem.sharedSecretKey(
      keyPair: senderKeyPair,
      remotePublicKey: recipientPublicKey,
    );
    return _extractAndExpand(
      dh: await dh.extractBytes(),
      kemContext: <int>[...encapsulatedKey, ...recipientPublicKey.bytes],
    );
  }

  Future<List<int>> _decap({
    required KeyPair recipientKeyPair,
    required List<int> recipientPublicKey,
    required List<int> encapsulatedKey,
  }) async {
    final dh = await _kem.sharedSecretKey(
      keyPair: recipientKeyPair,
      remotePublicKey: SimplePublicKey(
        encapsulatedKey,
        type: KeyPairType.x25519,
      ),
    );
    return _extractAndExpand(
      dh: await dh.extractBytes(),
      kemContext: <int>[...encapsulatedKey, ...recipientPublicKey],
    );
  }

  Future<List<int>> _extractAndExpand({
    required List<int> dh,
    required List<int> kemContext,
  }) async {
    if (dh.length != 32 || dh.every((byte) => byte == 0)) {
      throw const HpkeException('X25519 shared secret không hợp lệ.');
    }
    final eaePrk = await _labeledExtract(
      suiteId: _kemSuiteId,
      salt: const <int>[],
      label: 'eae_prk',
      inputKeyMaterial: dh,
    );
    return _labeledExpand(
      suiteId: _kemSuiteId,
      prk: eaePrk,
      label: 'shared_secret',
      info: kemContext,
      length: _hashLength,
    );
  }

  Future<_HpkeContext> _keySchedule({
    required List<int> sharedSecret,
    required List<int> info,
  }) async {
    final suiteId = <int>[
      ...ascii.encode('HPKE'),
      ..._i2osp(_kemId, 2),
      ..._i2osp(_kdfId, 2),
      ..._i2osp(aead.identifier, 2),
    ];
    final pskIdHash = await _labeledExtract(
      suiteId: suiteId,
      salt: const <int>[],
      label: 'psk_id_hash',
      inputKeyMaterial: const <int>[],
    );
    final infoHash = await _labeledExtract(
      suiteId: suiteId,
      salt: const <int>[],
      label: 'info_hash',
      inputKeyMaterial: info,
    );
    final keyScheduleContext = <int>[_modeBase, ...pskIdHash, ...infoHash];
    final secret = await _labeledExtract(
      suiteId: suiteId,
      salt: sharedSecret,
      label: 'secret',
      inputKeyMaterial: const <int>[],
    );
    final key = await _labeledExpand(
      suiteId: suiteId,
      prk: secret,
      label: 'key',
      info: keyScheduleContext,
      length: aead.keyLength,
    );
    final baseNonce = await _labeledExpand(
      suiteId: suiteId,
      prk: secret,
      label: 'base_nonce',
      info: keyScheduleContext,
      length: _nonceLength,
    );
    return _HpkeContext(key: key, baseNonce: baseNonce);
  }

  Future<List<int>> _labeledExtract({
    required List<int> suiteId,
    required List<int> salt,
    required String label,
    required List<int> inputKeyMaterial,
  }) async {
    final effectiveSalt = salt.isEmpty
        ? List<int>.filled(_hashLength, 0)
        : salt;
    final mac = await _hmac.calculateMac(<int>[
      ..._hpkeVersion,
      ...suiteId,
      ...ascii.encode(label),
      ...inputKeyMaterial,
    ], secretKey: SecretKey(effectiveSalt));
    return mac.bytes;
  }

  Future<List<int>> _labeledExpand({
    required List<int> suiteId,
    required List<int> prk,
    required String label,
    required List<int> info,
    required int length,
  }) async {
    if (length < 0 || length > 255 * _hashLength) {
      throw const HpkeException('HPKE output length không hợp lệ.');
    }
    final labeledInfo = <int>[
      ..._i2osp(length, 2),
      ..._hpkeVersion,
      ...suiteId,
      ...ascii.encode(label),
      ...info,
    ];
    final output = <int>[];
    var previous = <int>[];
    for (var counter = 1; output.length < length; counter++) {
      final mac = await _hmac.calculateMac(<int>[
        ...previous,
        ...labeledInfo,
        counter,
      ], secretKey: SecretKey(prk));
      previous = mac.bytes;
      output.addAll(previous);
    }
    return List<int>.unmodifiable(output.take(length));
  }

  static List<int> _i2osp(int value, int length) {
    if (value < 0 || value >= (1 << (8 * length))) {
      throw const HpkeException('HPKE integer encoding không hợp lệ.');
    }
    return List<int>.generate(
      length,
      (index) => (value >> (8 * (length - index - 1))) & 0xff,
    );
  }

  void _requireLength(List<int> bytes, int length, String field) {
    if (bytes.length != length) {
      throw HpkeException('$field có độ dài không hợp lệ.');
    }
  }
}

class _HpkeContext {
  final List<int> key;
  final List<int> baseNonce;

  const _HpkeContext({required this.key, required this.baseNonce});
}
