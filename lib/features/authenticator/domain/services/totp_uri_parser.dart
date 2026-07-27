import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

class ParsedTotpAccount extends Equatable {
  const ParsedTotpAccount({
    required this.issuer,
    required this.accountName,
    required this.secretKey,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  final String issuer;
  final String accountName;
  final String secretKey;
  final String algorithm;
  final int digits;
  final int period;

  @override
  List<Object?> get props => [
    issuer,
    accountName,
    secretKey,
    algorithm,
    digits,
    period,
  ];

  @override
  String toString() =>
      'ParsedTotpAccount('
      'issuer: [REDACTED], accountName: [REDACTED], '
      'secretKey: [REDACTED], algorithm: $algorithm, '
      'digits: $digits, period: $period)';
}

abstract final class TotpUriParser {
  static const _maxUriLength = 16 * 1024;

  static ParsedTotpAccount parse(String value) {
    final trimmed = value.trim();
    if (trimmed.length > _maxUriLength) {
      throw const FormatException('Mã QR TOTP vượt quá giới hạn an toàn.');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'otpauth' ||
        uri.host != 'totp' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 1) {
      throw const FormatException('Mã QR không phải tài khoản TOTP hợp lệ.');
    }

    final rawLabel = uri.pathSegments.single.trim();
    final issuerFromQuery = _singleQueryParameter(uri, 'issuer')?.trim() ?? '';
    final separatorIndex = rawLabel.indexOf(':');
    final exactIssuerPrefix =
        issuerFromQuery.isNotEmpty && rawLabel.startsWith('$issuerFromQuery:');
    final issuerFromLabel = separatorIndex > 0
        ? rawLabel.substring(0, separatorIndex).trim()
        : exactIssuerPrefix
        ? issuerFromQuery
        : '';
    final accountName = exactIssuerPrefix
        ? rawLabel.substring(issuerFromQuery.length + 1).trim()
        : separatorIndex >= 0
        ? rawLabel.substring(separatorIndex + 1).trim()
        : rawLabel.trim();
    final issuer = issuerFromQuery.isNotEmpty
        ? issuerFromQuery
        : issuerFromLabel;
    final secret = TotpValidator.normalizeSecret(
      _singleQueryParameter(uri, 'secret') ?? '',
    );
    final algorithm = TotpValidator.normalizeAlgorithm(
      _singleQueryParameter(uri, 'algorithm') ?? 'SHA1',
    );
    final digits = int.tryParse(_singleQueryParameter(uri, 'digits') ?? '6');
    final period = int.tryParse(_singleQueryParameter(uri, 'period') ?? '30');

    if (issuer.isEmpty || accountName.isEmpty) {
      throw const FormatException('Mã QR thiếu issuer hoặc tên tài khoản.');
    }
    if (digits == null || period == null) {
      throw const FormatException(
        'Digits hoặc period không phải là số hợp lệ.',
      );
    }
    TotpValidator.validateParameters(digits: digits, period: period);

    return ParsedTotpAccount(
      issuer: issuer,
      accountName: accountName,
      secretKey: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  static String? _singleQueryParameter(Uri uri, String name) {
    final values = uri.queryParametersAll[name];
    if (values == null) {
      return null;
    }
    if (values.length != 1) {
      throw const FormatException('Mã QR TOTP chứa tham số lặp không an toàn.');
    }
    return values.single;
  }
}
