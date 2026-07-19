import 'package:equatable/equatable.dart';

class DeviceWrappedVaultKey extends Equatable {
  static const currentFormatVersion = 1;
  static const kemName = 'DHKEM-X25519-HKDF-SHA256';
  static const kdfName = 'HKDF-SHA256';
  static const aeadName = 'AES-256-GCM';

  final int formatVersion;
  final int keyGeneration;
  final String kem;
  final String kdf;
  final String aead;
  final String encapsulatedKey;
  final String ciphertext;
  final String authTag;

  const DeviceWrappedVaultKey({
    required this.formatVersion,
    required this.keyGeneration,
    required this.kem,
    required this.kdf,
    required this.aead,
    required this.encapsulatedKey,
    required this.ciphertext,
    required this.authTag,
  });

  factory DeviceWrappedVaultKey.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['format_version'];
    final keyGeneration = json['key_generation'];
    final kem = json['kem'];
    final kdf = json['kdf'];
    final aead = json['aead'];
    final encapsulatedKey = json['encapsulated_key'];
    final ciphertext = json['ciphertext'];
    final authTag = json['auth_tag'];
    if (formatVersion is! int ||
        keyGeneration is! int ||
        keyGeneration < 1 ||
        kem is! String ||
        kdf is! String ||
        aead is! String ||
        encapsulatedKey is! String ||
        ciphertext is! String ||
        authTag is! String) {
      throw const FormatException('Device-wrapped vault key không hợp lệ.');
    }
    return DeviceWrappedVaultKey(
      formatVersion: formatVersion,
      keyGeneration: keyGeneration,
      kem: kem,
      kdf: kdf,
      aead: aead,
      encapsulatedKey: encapsulatedKey,
      ciphertext: ciphertext,
      authTag: authTag,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format_version': formatVersion,
    'key_generation': keyGeneration,
    'kem': kem,
    'kdf': kdf,
    'aead': aead,
    'encapsulated_key': encapsulatedKey,
    'ciphertext': ciphertext,
    'auth_tag': authTag,
  };

  @override
  List<Object?> get props => <Object?>[
    formatVersion,
    keyGeneration,
    kem,
    kdf,
    aead,
    encapsulatedKey,
    ciphertext,
    authTag,
  ];

  @override
  String toString() =>
      'DeviceWrappedVaultKey(generation: $keyGeneration, <redacted>)';
}

class DeviceKeyMaterial {
  final List<int> privateKeyBytes;
  final List<int> publicKeyBytes;
  final List<int> bindingSecretBytes;

  DeviceKeyMaterial({
    required List<int> privateKeyBytes,
    required List<int> publicKeyBytes,
    required List<int> bindingSecretBytes,
  }) : privateKeyBytes = List<int>.unmodifiable(privateKeyBytes),
       publicKeyBytes = List<int>.unmodifiable(publicKeyBytes),
       bindingSecretBytes = List<int>.unmodifiable(bindingSecretBytes);

  @override
  String toString() => 'DeviceKeyMaterial(<redacted>)';
}
