import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

class ParsedTotpAccount {
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
}

abstract final class TotpUriParser {
  static ParsedTotpAccount parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'otpauth' || uri.host != 'totp') {
      throw const FormatException('Mã QR không phải tài khoản TOTP hợp lệ.');
    }

    final rawLabel = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final separatorIndex = rawLabel.indexOf(':');
    final issuerFromLabel = separatorIndex > 0
        ? rawLabel.substring(0, separatorIndex).trim()
        : '';
    final accountName = separatorIndex >= 0
        ? rawLabel.substring(separatorIndex + 1).trim()
        : rawLabel.trim();
    final issuer = (uri.queryParameters['issuer']?.trim().isNotEmpty ?? false)
        ? uri.queryParameters['issuer']!.trim()
        : issuerFromLabel;
    final secret = TotpValidator.normalizeSecret(
      uri.queryParameters['secret'] ?? '',
    );
    final algorithm = TotpValidator.normalizeAlgorithm(
      uri.queryParameters['algorithm'] ?? 'SHA1',
    );
    final digits = int.tryParse(uri.queryParameters['digits'] ?? '6');
    final period = int.tryParse(uri.queryParameters['period'] ?? '30');

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
}
