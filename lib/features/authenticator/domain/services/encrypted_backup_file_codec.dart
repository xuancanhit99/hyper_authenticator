import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:injectable/injectable.dart';

sealed class BackupFileException implements Exception {
  const BackupFileException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType([REDACTED])';
}

final class BackupFormatException extends BackupFileException {
  const BackupFormatException(super.message);
}

final class BackupIntegrityException extends BackupFileException {
  const BackupIntegrityException()
    : super('Sai mật khẩu hoặc file backup đã bị thay đổi.');
}

final class BackupPasswordException extends BackupFileException {
  const BackupPasswordException(super.message);
}

class EncryptedBackupSnapshot {
  EncryptedBackupSnapshot({
    required this.formatVersion,
    required this.createdAt,
    required List<AuthenticatorAccount> accounts,
  }) : accounts = List<AuthenticatorAccount>.unmodifiable(accounts);

  final int formatVersion;
  final DateTime createdAt;
  final List<AuthenticatorAccount> accounts;

  @override
  String toString() =>
      'EncryptedBackupSnapshot(formatVersion: $formatVersion, '
      'createdAt: $createdAt, accounts: [${accounts.length} REDACTED])';
}

typedef BackupRandomBytes = List<int> Function(int length);
typedef BackupClock = DateTime Function();

/// Codec portable độc lập với Supabase identity và cloud-vault envelope.
///
/// JSON được yêu cầu ở canonical compact form để duplicate key, alternate
/// encoding và parser ambiguity không trở thành một phần ngầm của file contract.
@lazySingleton
class EncryptedBackupFileCodec {
  static const String fileExtension = 'hyauth';
  static const String formatName = 'hyper-authenticator-encrypted-backup';
  static const int currentFormatVersion = 1;
  static const int currentPayloadFormatVersion = 1;
  static const int defaultMemoryKiB = 19 * 1024;
  static const int defaultIterations = 2;
  static const int defaultParallelism = 1;
  static const int maximumMemoryKiB = 64 * 1024;
  static const int maximumFileBytes = 8 * 1024 * 1024;
  static const int maximumAccountCount = 10000;

  static const int _argon2Version = 19;
  static const int _keyLength = 32;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _maximumIterations = 5;
  static const int _maximumParallelism = 4;
  static const int _minimumPasswordCodePoints = 12;
  static const int _maximumPasswordBytes = 1024;
  static const int _maximumIdBytes = 128;
  static const int _maximumLabelBytes = 1024;
  static const int _maximumSecretBytes = 4096;
  static const int _maximumPeriodSeconds = 86400;
  static const String _cipherName = 'aes-256-gcm';
  static const String _kdfName = 'argon2id';

  final int _encoderMemoryKiB;
  final int _encoderIterations;
  final int _encoderParallelism;
  final int _minimumAcceptedMemoryKiB;
  final int _minimumAcceptedIterations;
  final BackupRandomBytes _randomBytes;
  final BackupClock _now;
  final AesGcm _cipher;

  EncryptedBackupFileCodec()
    : this._(
        encoderMemoryKiB: defaultMemoryKiB,
        encoderIterations: defaultIterations,
        encoderParallelism: defaultParallelism,
        minimumAcceptedMemoryKiB: defaultMemoryKiB,
        minimumAcceptedIterations: defaultIterations,
        randomBytes: _secureRandomBytes,
        now: DateTime.now,
        cipher: AesGcm.with256bits(),
      );

  EncryptedBackupFileCodec._({
    required this._encoderMemoryKiB,
    required this._encoderIterations,
    required this._encoderParallelism,
    required this._minimumAcceptedMemoryKiB,
    required this._minimumAcceptedIterations,
    required this._randomBytes,
    required this._now,
    required this._cipher,
  });

  factory EncryptedBackupFileCodec.forTesting({
    required int memoryKiB,
    required int iterations,
    int parallelism = 1,
    required BackupRandomBytes randomBytes,
    required BackupClock now,
  }) {
    if (memoryKiB < 8 * parallelism ||
        memoryKiB > maximumMemoryKiB ||
        iterations < 1 ||
        iterations > _maximumIterations ||
        parallelism < 1 ||
        parallelism > _maximumParallelism) {
      throw ArgumentError('Test KDF parameters không hợp lệ.');
    }
    return EncryptedBackupFileCodec._(
      encoderMemoryKiB: memoryKiB,
      encoderIterations: iterations,
      encoderParallelism: parallelism,
      minimumAcceptedMemoryKiB: memoryKiB,
      minimumAcceptedIterations: iterations,
      randomBytes: randomBytes,
      now: now,
      cipher: AesGcm.with256bits(),
    );
  }

  Future<Uint8List> encrypt({
    required List<AuthenticatorAccount> accounts,
    required String password,
  }) async {
    _validateAccounts(accounts);
    final passwordBytes = _validatePassword(password);
    SecretKey? derivedKey;
    Uint8List? payload;
    try {
      final salt = Uint8List.fromList(_randomBytes(_saltLength));
      final nonce = Uint8List.fromList(_randomBytes(_nonceLength));
      if (salt.length != _saltLength || nonce.length != _nonceLength) {
        throw const BackupFormatException(
          'Nguồn random không trả đúng số byte yêu cầu.',
        );
      }
      final kdf = _kdfMap(
        memoryKiB: _encoderMemoryKiB,
        iterations: _encoderIterations,
        parallelism: _encoderParallelism,
        salt: _encodeBytes(salt),
      );
      final cipherHeader = _cipherHeaderMap(nonce: _encodeBytes(nonce));
      final aad = _aadBytes(
        formatVersion: currentFormatVersion,
        kdf: kdf,
        cipherHeader: cipherHeader,
      );
      final createdAt = _now().toUtc();
      payload = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'payload_format_version': currentPayloadFormatVersion,
            'created_at': createdAt.toIso8601String(),
            'accounts': accounts.map((account) => account.toJson()).toList(),
          }),
        ),
      );
      derivedKey = await _deriveKey(
        passwordBytes: passwordBytes,
        salt: salt,
        memoryKiB: _encoderMemoryKiB,
        iterations: _encoderIterations,
        parallelism: _encoderParallelism,
      );
      final secretBox = await _cipher.encrypt(
        payload,
        secretKey: derivedKey,
        nonce: nonce,
        aad: aad,
      );
      final encoded = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'format': formatName,
            'format_version': currentFormatVersion,
            'kdf': kdf,
            'cipher': <String, dynamic>{
              ...cipherHeader,
              'ciphertext': _encodeBytes(secretBox.cipherText),
              'auth_tag': _encodeBytes(secretBox.mac.bytes),
            },
          }),
        ),
      );
      if (encoded.length > maximumFileBytes) {
        encoded.fillRange(0, encoded.length, 0);
        throw const BackupFormatException(
          'Snapshot vượt giới hạn 8 MiB của file backup.',
        );
      }
      return encoded;
    } on BackupFileException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException('Không thể tạo file backup mã hóa.');
    } finally {
      derivedKey?.destroy();
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      payload?.fillRange(0, payload.length, 0);
    }
  }

  Future<EncryptedBackupSnapshot> decrypt({
    required List<int> fileBytes,
    required String password,
  }) async {
    if (fileBytes.isEmpty || fileBytes.length > maximumFileBytes) {
      throw const BackupFormatException(
        'File backup rỗng hoặc vượt giới hạn 8 MiB.',
      );
    }
    final passwordBytes = _validatePassword(password);
    SecretKey? derivedKey;
    Uint8List? clearText;
    try {
      final rawJson = utf8.decode(fileBytes, allowMalformed: false);
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic> ||
          jsonEncode(decoded) != rawJson ||
          !_hasExactKeys(decoded, const {
            'format',
            'format_version',
            'kdf',
            'cipher',
          }) ||
          decoded['format'] != formatName ||
          decoded['format_version'] != currentFormatVersion) {
        throw const BackupFormatException(
          'File backup không đúng canonical schema v1.',
        );
      }

      final kdf = _requireMap(decoded['kdf'], 'KDF metadata');
      final cipher = _requireMap(decoded['cipher'], 'Cipher metadata');
      if (!_hasExactKeys(kdf, const {
            'name',
            'version',
            'memory_kib',
            'iterations',
            'parallelism',
            'salt',
          }) ||
          !_hasExactKeys(cipher, const {
            'name',
            'nonce',
            'ciphertext',
            'auth_tag',
          })) {
        throw const BackupFormatException('Envelope metadata không hợp lệ.');
      }

      final memoryKiB = _requireInt(kdf['memory_kib'], 'Argon2 memory');
      final iterations = _requireInt(kdf['iterations'], 'Argon2 iterations');
      final parallelism = _requireInt(kdf['parallelism'], 'Argon2 parallelism');
      if (kdf['name'] != _kdfName ||
          kdf['version'] != _argon2Version ||
          memoryKiB < _minimumAcceptedMemoryKiB ||
          memoryKiB > maximumMemoryKiB ||
          iterations < _minimumAcceptedIterations ||
          iterations > _maximumIterations ||
          parallelism < 1 ||
          parallelism > _maximumParallelism ||
          memoryKiB < 8 * parallelism) {
        throw const BackupFormatException(
          'Argon2id version hoặc resource parameters không được hỗ trợ.',
        );
      }
      if (cipher['name'] != _cipherName) {
        throw const BackupFormatException('Cipher không được hỗ trợ.');
      }

      late final Uint8List salt;
      late final Uint8List nonce;
      late final Uint8List ciphertext;
      late final Uint8List authTag;
      try {
        salt = _decodeBytes(
          kdf['salt'],
          fieldName: 'salt',
          exactLength: _saltLength,
        );
        nonce = _decodeBytes(
          cipher['nonce'],
          fieldName: 'nonce',
          exactLength: _nonceLength,
        );
        ciphertext = _decodeBytes(
          cipher['ciphertext'],
          fieldName: 'ciphertext',
        );
        authTag = _decodeBytes(
          cipher['auth_tag'],
          fieldName: 'auth_tag',
          exactLength: _tagLength,
        );
      } on BackupFormatException {
        throw const BackupIntegrityException();
      }
      if (ciphertext.isEmpty) {
        throw const BackupFormatException('Ciphertext rỗng.');
      }

      final cipherHeader = _cipherHeaderMap(nonce: cipher['nonce'] as String);
      final aad = _aadBytes(
        formatVersion: currentFormatVersion,
        kdf: kdf,
        cipherHeader: cipherHeader,
      );
      derivedKey = await _deriveKey(
        passwordBytes: passwordBytes,
        salt: salt,
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
      );
      try {
        clearText = Uint8List.fromList(
          await _cipher.decrypt(
            SecretBox(ciphertext, nonce: nonce, mac: Mac(authTag)),
            secretKey: derivedKey,
            aad: aad,
          ),
        );
      } catch (_) {
        throw const BackupIntegrityException();
      }

      return _decodePayload(clearText);
    } on BackupFileException {
      rethrow;
    } on FormatException {
      throw const BackupFormatException('Encoding file backup không hợp lệ.');
    } catch (_) {
      throw const BackupFormatException('Không thể đọc file backup.');
    } finally {
      derivedKey?.destroy();
      passwordBytes.fillRange(0, passwordBytes.length, 0);
      clearText?.fillRange(0, clearText.length, 0);
    }
  }

  EncryptedBackupSnapshot _decodePayload(Uint8List clearText) {
    try {
      final rawJson = utf8.decode(clearText, allowMalformed: false);
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic> ||
          jsonEncode(decoded) != rawJson ||
          !_hasExactKeys(decoded, const {
            'payload_format_version',
            'created_at',
            'accounts',
          }) ||
          decoded['payload_format_version'] != currentPayloadFormatVersion ||
          decoded['created_at'] is! String ||
          decoded['accounts'] is! List<dynamic>) {
        throw const BackupFormatException(
          'Plaintext payload không đúng canonical schema v1.',
        );
      }
      final createdAtText = decoded['created_at'] as String;
      final createdAt = DateTime.parse(createdAtText);
      if (!createdAt.isUtc || createdAt.toIso8601String() != createdAtText) {
        throw const BackupFormatException(
          'Timestamp backup không phải UTC canonical.',
        );
      }

      final rawAccounts = decoded['accounts'] as List<dynamic>;
      if (rawAccounts.length > maximumAccountCount) {
        throw const BackupFormatException(
          'File backup vượt giới hạn số tài khoản.',
        );
      }
      final accounts = <AuthenticatorAccount>[];
      for (final rawAccount in rawAccounts) {
        final accountMap = _requireMap(rawAccount, 'Account payload');
        if (!_hasExactKeys(accountMap, const {
          'id',
          'issuer',
          'accountName',
          'secretKey',
          'algorithm',
          'digits',
          'period',
        })) {
          throw const BackupFormatException('Account schema không hợp lệ.');
        }
        accounts.add(AuthenticatorAccount.fromJson(accountMap));
      }
      _validateAccounts(accounts);
      return EncryptedBackupSnapshot(
        formatVersion: currentPayloadFormatVersion,
        createdAt: createdAt,
        accounts: accounts,
      );
    } on BackupFileException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException(
        'Plaintext payload chứa dữ liệu không hợp lệ.',
      );
    }
  }

  Future<SecretKey> _deriveKey({
    required Uint8List passwordBytes,
    required Uint8List salt,
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) async {
    final state = DartArgon2id(
      parallelism: parallelism,
      memory: memoryKiB,
      iterations: iterations,
      hashLength: _keyLength,
    ).newState();
    try {
      final bytes = await state.deriveKeyBytes(
        password: passwordBytes,
        nonce: salt,
      );
      return SecretKeyData(
        bytes,
        overwriteWhenDestroyed: true,
        debugLabel: 'encrypted-backup-derived-key',
      );
    } finally {
      state.tryReleaseMemory();
    }
  }

  Uint8List _validatePassword(String password) {
    final bytes = Uint8List.fromList(utf8.encode(password));
    if (password.runes.length < _minimumPasswordCodePoints ||
        bytes.length > _maximumPasswordBytes ||
        password.trim().isEmpty) {
      bytes.fillRange(0, bytes.length, 0);
      throw const BackupPasswordException(
        'Password phải có ít nhất 12 ký tự và không vượt 1.024 byte.',
      );
    }
    return bytes;
  }

  void _validateAccounts(List<AuthenticatorAccount> accounts) {
    if (accounts.length > maximumAccountCount) {
      throw const BackupFormatException(
        'Snapshot vượt giới hạn 10.000 tài khoản.',
      );
    }
    final ids = <String>{};
    for (final account in accounts) {
      if (account.id.isEmpty ||
          !ids.add(account.id) ||
          utf8.encode(account.id).length > _maximumIdBytes ||
          account.issuer.trim().isEmpty ||
          account.issuer != account.issuer.trim() ||
          utf8.encode(account.issuer).length > _maximumLabelBytes ||
          account.accountName.trim().isEmpty ||
          account.accountName != account.accountName.trim() ||
          utf8.encode(account.accountName).length > _maximumLabelBytes ||
          utf8.encode(account.secretKey).length > _maximumSecretBytes ||
          account.period > _maximumPeriodSeconds) {
        throw const BackupFormatException(
          'Account identity, field limit hoặc stable ID không hợp lệ.',
        );
      }
      try {
        if (TotpValidator.normalizeSecret(account.secretKey) !=
                account.secretKey ||
            TotpValidator.normalizeAlgorithm(account.algorithm) !=
                account.algorithm) {
          throw const FormatException('TOTP field chưa canonical.');
        }
        TotpValidator.validateParameters(
          digits: account.digits,
          period: account.period,
        );
      } on FormatException {
        throw const BackupFormatException(
          'Account chứa TOTP semantics không hợp lệ.',
        );
      }
    }
  }

  Map<String, dynamic> _kdfMap({
    required int memoryKiB,
    required int iterations,
    required int parallelism,
    required String salt,
  }) => <String, dynamic>{
    'name': _kdfName,
    'version': _argon2Version,
    'memory_kib': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'salt': salt,
  };

  Map<String, dynamic> _cipherHeaderMap({required String nonce}) =>
      <String, dynamic>{'name': _cipherName, 'nonce': nonce};

  Uint8List _aadBytes({
    required int formatVersion,
    required Map<String, dynamic> kdf,
    required Map<String, dynamic> cipherHeader,
  }) => Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'purpose': 'hyper-authenticator:encrypted-backup',
        'format': formatName,
        'format_version': formatVersion,
        'kdf': kdf,
        'cipher': cipherHeader,
      }),
    ),
  );

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length &&
      value.keys.toSet().containsAll(expected);

  static Map<String, dynamic> _requireMap(Object? value, String fieldName) {
    if (value is! Map<String, dynamic>) {
      throw BackupFormatException('$fieldName không phải object.');
    }
    return value;
  }

  static int _requireInt(Object? value, String fieldName) {
    if (value is! int) {
      throw BackupFormatException('$fieldName không phải số nguyên.');
    }
    return value;
  }

  static String _encodeBytes(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List _decodeBytes(
    Object? value, {
    required String fieldName,
    int? exactLength,
  }) {
    if (value is! String || value.isEmpty || value.contains('=')) {
      throw BackupFormatException('$fieldName không đúng Base64URL canonical.');
    }
    try {
      final padding = '=' * ((4 - value.length % 4) % 4);
      final bytes = Uint8List.fromList(base64Url.decode('$value$padding'));
      if (_encodeBytes(bytes) != value ||
          (exactLength != null && bytes.length != exactLength)) {
        throw const FormatException();
      }
      return bytes;
    } catch (_) {
      throw BackupFormatException('$fieldName không đúng Base64URL canonical.');
    }
  }
}
