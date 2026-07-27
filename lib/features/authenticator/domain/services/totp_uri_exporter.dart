import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

/// Một QR chuẩn `otpauth://totp` chứa credential của đúng một tài khoản.
///
/// Không log object này hoặc đưa [uri] vào analytics, BLoC hay route arguments.
class TotpUriExportPart {
  const TotpUriExportPart._({
    required this.uri,
    required this.index,
    required this.total,
  });

  final String uri;
  final int index;
  final int total;

  @override
  String toString() =>
      'TotpUriExportPart('
      'uri: [REDACTED], index: $index, total: $total)';
}

/// Encoder bounded cho standard Key URI Format `otpauth://totp`.
///
/// Mỗi account được encode thành một QR độc lập để giữ algorithm, digits và
/// period mà không tạo container proprietary.
abstract final class TotpUriExporter {
  static const _maxAccounts = 100;
  static const _maxEncodedUriLength = 1800;

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
      _buildUri(account);
    }
  }

  static List<TotpUriExportPart> export(List<AuthenticatorAccount> accounts) {
    validateAccounts(accounts);
    return List<TotpUriExportPart>.unmodifiable([
      for (var index = 0; index < accounts.length; index++)
        TotpUriExportPart._(
          uri: _buildUri(accounts[index]),
          index: index,
          total: accounts.length,
        ),
    ]);
  }

  static String _buildUri(AuthenticatorAccount account) {
    final issuer = account.issuer.trim();
    final accountName = account.accountName.trim();
    if (issuer.isEmpty || accountName.isEmpty) {
      throw const FormatException(
        'Tài khoản export phải có issuer và tên tài khoản.',
      );
    }

    final secret = TotpValidator.normalizeSecret(
      account.secretKey,
    ).replaceAll('=', '');
    final algorithm = TotpValidator.normalizeAlgorithm(account.algorithm);
    TotpValidator.validateParameters(
      digits: account.digits,
      period: account.period,
    );

    final uri = Uri(
      scheme: 'otpauth',
      host: 'totp',
      pathSegments: ['$issuer:$accountName'],
      queryParameters: {
        'secret': secret,
        'issuer': issuer,
        'algorithm': algorithm,
        'digits': account.digits.toString(),
        'period': account.period.toString(),
      },
    ).toString();
    if (uri.length > _maxEncodedUriLength) {
      throw const FormatException(
        'Tên hoặc dữ liệu của một tài khoản quá dài để tạo QR an toàn.',
      );
    }
    return uri;
  }
}
