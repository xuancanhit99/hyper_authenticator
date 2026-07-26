import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

/// Parsed form of one Google Authenticator migration QR.
///
/// The migration wire schema is not a public Google API. Keep this parser
/// bounded and fail closed when the version or an OTP enum is unknown.
class GoogleAuthenticatorMigrationPayload extends Equatable {
  GoogleAuthenticatorMigrationPayload({
    required List<ParsedTotpAccount> accounts,
    required this.version,
    required this.batchSize,
    required this.batchIndex,
    required this.batchId,
  }) : accounts = List<ParsedTotpAccount>.unmodifiable(accounts);

  final List<ParsedTotpAccount> accounts;
  final int version;
  final int batchSize;
  final int batchIndex;
  final int batchId;

  @override
  List<Object?> get props => [
    accounts,
    version,
    batchSize,
    batchIndex,
    batchId,
  ];

  @override
  String toString() =>
      'GoogleAuthenticatorMigrationPayload('
      'accounts: [${accounts.length} REDACTED], version: $version, '
      'batchSize: $batchSize, batchIndex: $batchIndex, '
      'batchId: [REDACTED])';
}

class GoogleAuthenticatorMigrationBatchProgress {
  GoogleAuthenticatorMigrationBatchProgress._({
    required this.scannedParts,
    required this.totalParts,
    required List<ParsedTotpAccount>? accounts,
  }) : accounts = accounts == null
           ? null
           : List<ParsedTotpAccount>.unmodifiable(accounts);

  final int scannedParts;
  final int totalParts;
  final List<ParsedTotpAccount>? accounts;

  bool get isComplete => accounts != null;
}

/// In-memory collector for a possibly multi-part Google migration export.
///
/// No payload is persisted here. A complete result is returned only when every
/// index in the same batch has been scanned.
class GoogleAuthenticatorMigrationBatchCollector {
  static const _maxCollectedAccounts = 100;

  final Map<int, GoogleAuthenticatorMigrationPayload> _parts =
      <int, GoogleAuthenticatorMigrationPayload>{};

  int? _version;
  int? _batchSize;
  int? _batchId;

  int get scannedParts => _parts.length;
  int get totalParts => _batchSize ?? 0;
  bool get hasPendingBatch => _parts.isNotEmpty;

  GoogleAuthenticatorMigrationBatchProgress add(
    GoogleAuthenticatorMigrationPayload payload,
  ) {
    if (_parts.isEmpty) {
      _version = payload.version;
      _batchSize = payload.batchSize;
      _batchId = payload.batchId;
    } else if (payload.version != _version ||
        payload.batchSize != _batchSize ||
        payload.batchId != _batchId) {
      throw const FormatException(
        'Mã QR thuộc một đợt export Google Authenticator khác.',
      );
    }

    final existing = _parts[payload.batchIndex];
    if (existing != null && existing != payload) {
      throw const FormatException(
        'Một phần của đợt export có dữ liệu không nhất quán.',
      );
    }
    if (existing == null) {
      final collectedAccountCount = _parts.values.fold<int>(
        payload.accounts.length,
        (total, part) => total + part.accounts.length,
      );
      if (collectedAccountCount > _maxCollectedAccounts) {
        throw const FormatException(
          'Đợt export Google Authenticator chứa quá nhiều tài khoản.',
        );
      }
    }
    _parts[payload.batchIndex] = payload;

    if (_parts.length != _batchSize) {
      return GoogleAuthenticatorMigrationBatchProgress._(
        scannedParts: _parts.length,
        totalParts: _batchSize!,
        accounts: null,
      );
    }

    final accounts = <ParsedTotpAccount>[
      for (var index = 0; index < _batchSize!; index++)
        ..._parts[index]!.accounts,
    ];
    final totalParts = _batchSize!;
    clear();
    return GoogleAuthenticatorMigrationBatchProgress._(
      scannedParts: totalParts,
      totalParts: totalParts,
      accounts: accounts,
    );
  }

  void clear() {
    _parts.clear();
    _version = null;
    _batchSize = null;
    _batchId = null;
  }
}

abstract final class GoogleAuthenticatorMigrationParser {
  static const _supportedVersions = {1, 2};
  static const _maxEncodedUriLength = 96 * 1024;
  static const _maxPayloadBytes = 64 * 1024;
  static const _maxAccounts = 100;
  static const _maxBatchParts = 100;
  static const _maxSecretBytes = 1024;
  static const _maxTextBytes = 2048;
  static const _maxVersionTwoIdentifierBytes = 256;

  static bool isMigrationUri(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri?.scheme == 'otpauth-migration' && uri?.host == 'offline';
  }

  static GoogleAuthenticatorMigrationPayload parse(String value) {
    final trimmed = value.trim();
    if (trimmed.length > _maxEncodedUriLength) {
      throw const FormatException(
        'Payload Google Authenticator vượt quá giới hạn an toàn.',
      );
    }

    final Uri uri;
    try {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null ||
          parsed.scheme != 'otpauth-migration' ||
          parsed.host != 'offline') {
        throw const FormatException(
          'Mã QR không phải export Google Authenticator hợp lệ.',
        );
      }
      uri = parsed;
    } on FormatException {
      throw const FormatException(
        'Mã QR không phải export Google Authenticator hợp lệ.',
      );
    }

    final dataValues = uri.queryParametersAll['data'];
    if (dataValues == null ||
        dataValues.length != 1 ||
        dataValues.single.isEmpty) {
      throw const FormatException(
        'Export Google Authenticator thiếu payload data.',
      );
    }

    final Uint8List payloadBytes;
    try {
      final encoded = dataValues.single.replaceAll(' ', '+');
      payloadBytes = base64.decode(base64.normalize(encoded));
    } on FormatException {
      throw const FormatException(
        'Payload Google Authenticator không phải Base64 hợp lệ.',
      );
    }
    if (payloadBytes.isEmpty || payloadBytes.length > _maxPayloadBytes) {
      throw const FormatException(
        'Payload Google Authenticator có kích thước không hợp lệ.',
      );
    }

    return _parsePayload(payloadBytes);
  }

  static GoogleAuthenticatorMigrationPayload _parsePayload(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    final encodedAccounts = <Uint8List>[];
    int? version;
    int? batchSize;
    // Proto3 omits scalar fields whose value is the default. The first batch
    // part therefore commonly has no encoded batch_index field.
    var batchIndex = 0;
    var batchId = 0;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          _requireWireType(wireType, 2);
          if (encodedAccounts.length >= _maxAccounts) {
            throw const FormatException(
              'Export Google Authenticator chứa quá nhiều tài khoản.',
            );
          }
          encodedAccounts.add(
            reader.readLengthDelimited(maxLength: _maxPayloadBytes),
          );
        case 2:
          _requireWireType(wireType, 0);
          version = _readPositiveInt32(reader, fieldName: 'version');
        case 3:
          _requireWireType(wireType, 0);
          batchSize = _readPositiveInt32(reader, fieldName: 'batch_size');
        case 4:
          _requireWireType(wireType, 0);
          batchIndex = _readNonNegativeInt32(reader, fieldName: 'batch_index');
        case 5:
          _requireWireType(wireType, 0);
          batchId = _readInt32(reader, fieldName: 'batch_id');
        default:
          throw const FormatException(
            'Google Authenticator export chứa metadata chưa được hỗ trợ.',
          );
      }
    }

    if (encodedAccounts.isEmpty) {
      throw const FormatException(
        'Export Google Authenticator không chứa tài khoản.',
      );
    }
    if (!_supportedVersions.contains(version)) {
      throw const FormatException(
        'Version export Google Authenticator chưa được hỗ trợ.',
      );
    }
    if (batchSize == null ||
        batchSize > _maxBatchParts ||
        batchIndex >= batchSize) {
      throw const FormatException(
        'Metadata batch Google Authenticator không hợp lệ.',
      );
    }

    final accounts = [
      for (final encodedAccount in encodedAccounts)
        _parseOtpParameters(encodedAccount, version: version!),
    ];
    return GoogleAuthenticatorMigrationPayload(
      accounts: accounts,
      version: version!,
      batchSize: batchSize,
      batchIndex: batchIndex,
      batchId: batchId,
    );
  }

  static ParsedTotpAccount _parseOtpParameters(
    Uint8List bytes, {
    required int version,
  }) {
    final reader = _ProtoReader(bytes);
    Uint8List? secretBytes;
    String name = '';
    String issuer = '';
    var algorithmValue = 0;
    var digitsValue = 0;
    var typeValue = 0;
    var hasVersionTwoIdentifier = false;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      final field = tag >> 3;
      final wireType = tag & 7;
      switch (field) {
        case 1:
          _requireWireType(wireType, 2);
          secretBytes = reader.readLengthDelimited(maxLength: _maxSecretBytes);
        case 2:
          _requireWireType(wireType, 2);
          name = _decodeText(
            reader.readLengthDelimited(maxLength: _maxTextBytes),
          );
        case 3:
          _requireWireType(wireType, 2);
          issuer = _decodeText(
            reader.readLengthDelimited(maxLength: _maxTextBytes),
          );
        case 4:
          _requireWireType(wireType, 0);
          algorithmValue = _readNonNegativeInt32(
            reader,
            fieldName: 'algorithm',
          );
        case 5:
          _requireWireType(wireType, 0);
          digitsValue = _readNonNegativeInt32(reader, fieldName: 'digits');
        case 6:
          _requireWireType(wireType, 0);
          typeValue = _readNonNegativeInt32(reader, fieldName: 'type');
        case 7:
          _requireWireType(wireType, 0);
          reader.readVarint();
        case 8:
          if (version != 2 || hasVersionTwoIdentifier) {
            throw const FormatException(
              'Google Authenticator export chứa metadata tài khoản chưa được hỗ trợ.',
            );
          }
          _requireWireType(wireType, 2);
          final identifier = reader.readLengthDelimited(
            maxLength: _maxVersionTwoIdentifierBytes,
          );
          if (identifier.isEmpty) {
            throw const FormatException(
              'Google Authenticator export chứa identifier không hợp lệ.',
            );
          }
          hasVersionTwoIdentifier = true;
        default:
          throw const FormatException(
            'Google Authenticator export chứa metadata tài khoản chưa được hỗ trợ.',
          );
      }
    }

    if (secretBytes == null || secretBytes.isEmpty) {
      throw const FormatException(
        'Một tài khoản Google Authenticator thiếu secret.',
      );
    }

    final algorithm = switch (algorithmValue) {
      0 || 1 => 'SHA1',
      2 => 'SHA256',
      3 => 'SHA512',
      4 => throw const FormatException(
        'Google Authenticator export chứa thuật toán MD5 chưa được hỗ trợ.',
      ),
      _ => throw const FormatException(
        'Google Authenticator export chứa thuật toán không hỗ trợ.',
      ),
    };
    final digits = switch (digitsValue) {
      0 || 1 => 6,
      2 => 8,
      _ => throw const FormatException(
        'Google Authenticator export chứa số chữ số OTP không hỗ trợ.',
      ),
    };
    if (typeValue != 0 && typeValue != 2) {
      throw FormatException(
        typeValue == 1
            ? 'HOTP chưa được hỗ trợ; không có tài khoản nào được import.'
            : 'Google Authenticator export chứa loại OTP không hỗ trợ.',
      );
    }

    final normalized = _normalizeLabel(name: name, issuer: issuer);
    final secret = TotpValidator.normalizeSecret(
      base32.encode(secretBytes).replaceAll('=', ''),
    );
    TotpValidator.validateParameters(digits: digits, period: 30);

    return ParsedTotpAccount(
      issuer: normalized.$1,
      accountName: normalized.$2,
      secretKey: secret,
      algorithm: algorithm,
      digits: digits,
      period: 30,
    );
  }

  static (String, String) _normalizeLabel({
    required String name,
    required String issuer,
  }) {
    var normalizedIssuer = issuer.trim();
    var accountName = name.trim();
    if (normalizedIssuer.isNotEmpty) {
      final prefix = '$normalizedIssuer:';
      if (accountName.toLowerCase().startsWith(prefix.toLowerCase())) {
        accountName = accountName.substring(prefix.length).trim();
      }
    } else {
      final separator = accountName.indexOf(':');
      if (separator > 0) {
        normalizedIssuer = accountName.substring(0, separator).trim();
        accountName = accountName.substring(separator + 1).trim();
      }
    }

    if (accountName.isEmpty) {
      throw const FormatException(
        'Một tài khoản Google Authenticator thiếu tên tài khoản.',
      );
    }
    if (normalizedIssuer.isEmpty) {
      normalizedIssuer = 'Không xác định';
    }
    return (normalizedIssuer, accountName);
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException(
        'Google Authenticator export chứa text UTF-8 không hợp lệ.',
      );
    }
  }

  static int _readPositiveInt32(
    _ProtoReader reader, {
    required String fieldName,
  }) {
    final value = _readNonNegativeInt32(reader, fieldName: fieldName);
    if (value == 0) {
      throw FormatException('Metadata $fieldName phải lớn hơn 0.');
    }
    return value;
  }

  static int _readNonNegativeInt32(
    _ProtoReader reader, {
    required String fieldName,
  }) {
    final value = reader.readVarint();
    if (value > 0x7fffffff) {
      throw FormatException('Metadata $fieldName vượt giới hạn int32.');
    }
    return value;
  }

  static int _readInt32(_ProtoReader reader, {required String fieldName}) {
    try {
      return reader.readInt32();
    } on FormatException {
      throw FormatException('Metadata $fieldName vượt giới hạn int32.');
    }
  }

  static void _requireWireType(int actual, int expected) {
    if (actual != expected) {
      throw const FormatException(
        'Google Authenticator export có protobuf wire type không hợp lệ.',
      );
    }
  }
}

class _ProtoReader {
  _ProtoReader(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  bool get isAtEnd => _offset == bytes.length;

  int readTag() {
    final tag = readVarint();
    if (tag == 0 || tag >> 3 == 0) {
      throw const FormatException('Protobuf tag không hợp lệ.');
    }
    return tag;
  }

  int readVarint() {
    var result = 0;
    for (var byteIndex = 0; byteIndex < 10; byteIndex++) {
      if (_offset >= bytes.length) {
        throw const FormatException('Protobuf bị cắt giữa varint.');
      }
      final byte = bytes[_offset++];
      if (byteIndex == 9 && byte > 1) {
        throw const FormatException('Protobuf varint vượt giới hạn 64-bit.');
      }
      result |= (byte & 0x7f) << (byteIndex * 7);
      if ((byte & 0x80) == 0) {
        return result;
      }
    }
    throw const FormatException('Protobuf varint vượt giới hạn 64-bit.');
  }

  /// Reads protobuf `int32` without constructing an integer above 32 bits.
  ///
  /// Negative values use a ten-byte sign-extended varint. Decoding those bytes
  /// directly keeps this exact on JavaScript/Web and native Dart runtimes.
  int readInt32() {
    var lower32 = 0;
    for (var byteIndex = 0; byteIndex < 10; byteIndex++) {
      if (_offset >= bytes.length) {
        throw const FormatException('Protobuf bị cắt giữa int32.');
      }
      final byte = bytes[_offset++];
      final payload = byte & 0x7f;

      if (byteIndex < 4) {
        lower32 |= payload << (byteIndex * 7);
      } else if (byteIndex == 4) {
        lower32 |= (payload & 0x0f) << 28;
      }

      final isLast = (byte & 0x80) == 0;
      if (byteIndex < 4 && isLast) {
        return lower32;
      }
      if (byteIndex == 4) {
        if (isLast) {
          if ((payload & 0x70) != 0) {
            throw const FormatException('Protobuf int32 vượt 32 bit.');
          }
          return lower32 >= 0x80000000 ? lower32 - 0x100000000 : lower32;
        }
        if ((payload & 0x78) != 0x78) {
          throw const FormatException('Protobuf int32 sign extension sai.');
        }
      } else if (byteIndex > 4 && byteIndex < 9 && byte != 0xff) {
        throw const FormatException('Protobuf int32 sign extension sai.');
      } else if (byteIndex == 9) {
        if (byte != 0x01) {
          throw const FormatException('Protobuf int32 vượt 32 bit.');
        }
        return lower32 - 0x100000000;
      }

      if (isLast) {
        throw const FormatException('Protobuf int32 sign extension sai.');
      }
    }
    throw const FormatException('Protobuf int32 vượt 32 bit.');
  }

  Uint8List readLengthDelimited({required int maxLength}) {
    final length = readVarint();
    final remaining = bytes.length - _offset;
    if (length > maxLength || length > remaining) {
      throw const FormatException(
        'Protobuf length-delimited field không hợp lệ.',
      );
    }
    final result = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _skipBytes(8);
      case 2:
        final length = readVarint();
        _skipBytes(length);
      case 5:
        _skipBytes(4);
      default:
        throw const FormatException(
          'Protobuf chứa wire type chưa được hỗ trợ.',
        );
    }
  }

  void _skipBytes(int length) {
    if (length < 0 || length > bytes.length - _offset) {
      throw const FormatException('Protobuf field vượt khỏi payload.');
    }
    _offset += length;
  }
}
