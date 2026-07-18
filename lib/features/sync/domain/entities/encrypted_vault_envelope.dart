import 'package:equatable/equatable.dart';

class EncryptedVaultEnvelope extends Equatable {
  static const currentFormatVersion = 1;
  static const cipherName = 'AES-256-GCM';

  final int formatVersion;
  final int revision;
  final String cipher;
  final String nonce;
  final String ciphertext;
  final String authTag;

  const EncryptedVaultEnvelope({
    required this.formatVersion,
    required this.revision,
    required this.cipher,
    required this.nonce,
    required this.ciphertext,
    required this.authTag,
  });

  @override
  List<Object?> get props => [
    formatVersion,
    revision,
    cipher,
    nonce,
    ciphertext,
    authTag,
  ];

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format_version': formatVersion,
    'revision': revision,
    'cipher': cipher,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'auth_tag': authTag,
  };

  factory EncryptedVaultEnvelope.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['format_version'];
    final revision = json['revision'];
    final cipher = json['cipher'];
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final authTag = json['auth_tag'];
    if (formatVersion is! int ||
        revision is! int ||
        revision < 1 ||
        cipher is! String ||
        nonce is! String ||
        ciphertext is! String ||
        authTag is! String) {
      throw const FormatException('Encrypted vault envelope không hợp lệ.');
    }
    return EncryptedVaultEnvelope(
      formatVersion: formatVersion,
      revision: revision,
      cipher: cipher,
      nonce: nonce,
      ciphertext: ciphertext,
      authTag: authTag,
    );
  }
}

class WrappedVaultKey extends Equatable {
  static const currentFormatVersion = 1;

  final int formatVersion;
  final String cipher;
  final String nonce;
  final String ciphertext;
  final String authTag;

  const WrappedVaultKey({
    required this.formatVersion,
    required this.cipher,
    required this.nonce,
    required this.ciphertext,
    required this.authTag,
  });

  @override
  List<Object?> get props => [
    formatVersion,
    cipher,
    nonce,
    ciphertext,
    authTag,
  ];

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format_version': formatVersion,
    'cipher': cipher,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'auth_tag': authTag,
  };

  factory WrappedVaultKey.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['format_version'];
    final cipher = json['cipher'];
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final authTag = json['auth_tag'];
    if (formatVersion is! int ||
        cipher is! String ||
        nonce is! String ||
        ciphertext is! String ||
        authTag is! String) {
      throw const FormatException('Wrapped vault key không hợp lệ.');
    }
    return WrappedVaultKey(
      formatVersion: formatVersion,
      cipher: cipher,
      nonce: nonce,
      ciphertext: ciphertext,
      authTag: authTag,
    );
  }
}

class VaultKeyBundle {
  final List<int> dataKeyBytes;
  final String recoveryCode;
  final WrappedVaultKey wrappedDataKey;

  const VaultKeyBundle({
    required this.dataKeyBytes,
    required this.recoveryCode,
    required this.wrappedDataKey,
  });
}

class VaultRecoveryKeyBundle {
  final String recoveryCode;
  final WrappedVaultKey wrappedDataKey;

  const VaultRecoveryKeyBundle({
    required this.recoveryCode,
    required this.wrappedDataKey,
  });
}
