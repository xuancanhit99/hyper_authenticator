import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

/// Một phần QR trong đợt export Google Authenticator.
///
/// [uri] chứa TOTP secret. Không log object này hoặc đưa URI vào analytics.
class GoogleAuthenticatorMigrationExportPart {
  const GoogleAuthenticatorMigrationExportPart._({
    required this.uri,
    required this.index,
    required this.total,
  });

  final String uri;
  final int index;
  final int total;

  @override
  String toString() =>
      'GoogleAuthenticatorMigrationExportPart('
      'uri: [REDACTED], index: $index, total: $total)';
}

/// Encoder bounded cho reconstructed Google Authenticator migration schema v1.
///
/// Format này không phải public Google API. Encoder chỉ phát TOTP có semantics
/// Google migration biểu diễn được và giới hạn từng URI để QR mức sửa lỗi M vẫn
/// nằm dưới dung lượng byte-mode thực tế.
abstract final class GoogleAuthenticatorMigrationExporter {
  static const int _version = 1;
  static const int _maxAccounts = 100;
  static const int _maxParts = 100;
  static const int _maxSecretBytes = 1024;
  static const int _maxTextBytes = 2048;
  static const int _maxEncodedUriLength = 1800;

  static void validateAccounts(List<AuthenticatorAccount> accounts) {
    if (accounts.isEmpty) {
      throw const FormatException('Hãy chọn ít nhất một tài khoản để export.');
    }
    if (accounts.length > _maxAccounts) {
      throw const FormatException(
        'Mỗi đợt export hỗ trợ tối đa 100 tài khoản.',
      );
    }
    for (final account in accounts) {
      _encodeOtpParameters(account);
    }
  }

  static List<GoogleAuthenticatorMigrationExportPart> export(
    List<AuthenticatorAccount> accounts, {
    int? batchId,
  }) {
    validateAccounts(accounts);
    final resolvedBatchId =
        batchId ?? (Random.secure().nextInt(0x7ffffffe) + 1);
    if (resolvedBatchId <= 0 || resolvedBatchId > 0x7fffffff) {
      throw const FormatException('Batch ID export không hợp lệ.');
    }

    final encodedAccounts = accounts.map(_encodeOtpParameters).toList();
    final partitions = <List<Uint8List>>[];
    var current = <Uint8List>[];

    for (final encodedAccount in encodedAccounts) {
      final candidate = [...current, encodedAccount];
      final conservativeUri = _buildUri(
        candidate,
        batchSize: _maxParts,
        batchIndex: _maxParts - 1,
        batchId: resolvedBatchId,
      );
      if (conservativeUri.length <= _maxEncodedUriLength) {
        current = candidate;
        continue;
      }
      if (current.isEmpty) {
        throw const FormatException(
          'Tên hoặc dữ liệu của một tài khoản quá dài để tạo QR an toàn.',
        );
      }
      partitions.add(current);
      current = [encodedAccount];
      final singleUri = _buildUri(
        current,
        batchSize: _maxParts,
        batchIndex: _maxParts - 1,
        batchId: resolvedBatchId,
      );
      if (singleUri.length > _maxEncodedUriLength) {
        throw const FormatException(
          'Tên hoặc dữ liệu của một tài khoản quá dài để tạo QR an toàn.',
        );
      }
    }
    partitions.add(current);

    if (partitions.length > _maxParts) {
      throw const FormatException('Đợt export cần quá nhiều mã QR.');
    }

    return List<GoogleAuthenticatorMigrationExportPart>.unmodifiable([
      for (var index = 0; index < partitions.length; index++)
        GoogleAuthenticatorMigrationExportPart._(
          uri: _buildUri(
            partitions[index],
            batchSize: partitions.length,
            batchIndex: index,
            batchId: resolvedBatchId,
          ),
          index: index,
          total: partitions.length,
        ),
    ]);
  }

  static Uint8List _encodeOtpParameters(AuthenticatorAccount account) {
    final issuer = account.issuer.trim();
    final accountName = account.accountName.trim();
    if (issuer.isEmpty || accountName.isEmpty) {
      throw const FormatException(
        'Tài khoản export phải có issuer và tên tài khoản.',
      );
    }
    if (account.period != 30) {
      throw const FormatException(
        'Google Authenticator export chỉ hỗ trợ chu kỳ 30 giây.',
      );
    }

    final algorithm = switch (TotpValidator.normalizeAlgorithm(
      account.algorithm,
    )) {
      'SHA1' => 1,
      'SHA256' => 2,
      'SHA512' => 3,
      _ => throw const FormatException('Thuật toán TOTP chưa được hỗ trợ.'),
    };
    final digits = switch (account.digits) {
      6 => 1,
      8 => 2,
      _ => throw const FormatException(
        'Google Authenticator export chỉ hỗ trợ mã 6 hoặc 8 chữ số.',
      ),
    };
    final normalizedSecret = TotpValidator.normalizeSecret(account.secretKey);
    final secret = base32.decode(normalizedSecret);
    if (secret.isEmpty || secret.length > _maxSecretBytes) {
      throw const FormatException('Secret có kích thước không hợp lệ.');
    }

    final nameBytes = utf8.encode('$issuer:$accountName');
    final issuerBytes = utf8.encode(issuer);
    if (nameBytes.length > _maxTextBytes ||
        issuerBytes.length > _maxTextBytes) {
      throw const FormatException(
        'Tên hoặc issuer của tài khoản vượt quá giới hạn export.',
      );
    }

    final writer = _ProtoWriter()
      ..writeBytes(1, secret)
      ..writeBytes(2, nameBytes)
      ..writeBytes(3, issuerBytes)
      ..writeInt32(4, algorithm)
      ..writeInt32(5, digits)
      ..writeInt32(6, 2);
    return writer.takeBytes();
  }

  static String _buildUri(
    List<Uint8List> encodedAccounts, {
    required int batchSize,
    required int batchIndex,
    required int batchId,
  }) {
    final writer = _ProtoWriter();
    for (final account in encodedAccounts) {
      writer.writeBytes(1, account);
    }
    writer
      ..writeInt32(2, _version)
      ..writeInt32(3, batchSize)
      ..writeInt32(4, batchIndex)
      ..writeInt32(5, batchId);

    return Uri(
      scheme: 'otpauth-migration',
      host: 'offline',
      queryParameters: {'data': base64.encode(writer.takeBytes())},
    ).toString();
  }
}

class _ProtoWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void writeBytes(int field, List<int> value) {
    _writeVarint((field << 3) | 2);
    _writeVarint(value.length);
    _bytes.add(value);
  }

  void writeInt32(int field, int value) {
    _writeVarint(field << 3);
    _writeVarint(value);
  }

  Uint8List takeBytes() => _bytes.takeBytes();

  void _writeVarint(int value) {
    if (value < 0) {
      throw const FormatException('Không thể encode varint âm.');
    }
    var remaining = value;
    while (remaining >= 0x80) {
      _bytes.addByte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    _bytes.addByte(remaining);
  }
}
