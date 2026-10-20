import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

/// Shared admission/RPC limits from is_valid_authenticator_payload (ADR-0020).
/// Label lengths count Unicode code points, matching PostgreSQL char_length.
abstract final class AccountPayloadValidator {
  /// Keep the key bytes unchanged while meeting the existing RPC's encoded
  /// length minimum. Older padded 6–9 byte keys must remain editable.
  static String normalizeSecretForStorage(String value) {
    final secret = TotpValidator.normalizeSecret(value);
    return secret.length < 16
        ? secret.padRight(((secret.length + 7) ~/ 8) * 8, '=')
        : secret;
  }

  static void validateBounds({
    required String issuer,
    required String accountName,
    required String secretKey,
  }) {
    if (!_isJsonString(issuer) || !_isJsonString(accountName)) {
      throw const FormatException(
        'Tên dịch vụ hoặc tài khoản chứa ký tự không hợp lệ.',
      );
    }
    if (issuer.runes.length > 256) {
      throw const FormatException('Tên dịch vụ không được vượt quá 256 ký tự.');
    }
    if (accountName.isEmpty || accountName.runes.length > 512) {
      throw const FormatException('Tên tài khoản phải có từ 1 đến 512 ký tự.');
    }
    if (secretKey.length < 16 || secretKey.length > 1024) {
      throw const FormatException(
        'Khóa thiết lập phải có từ 16 đến 1024 ký tự Base32.',
      );
    }
  }

  // PostgreSQL jsonb rejects NUL and unpaired UTF-16 surrogates. Runes joins
  // valid surrogate pairs, so supplementary Unicode characters remain valid.
  static bool _isJsonString(String value) => value.runes.every(
    (rune) => rune != 0 && (rune < 0xd800 || rune > 0xdfff),
  );

  /// Validate existing records without rewriting or truncating stored secrets.
  /// Valid uppercase padded legacy Base32 is also permitted by the RPC schema.
  static void validateCloudAccount(AuthenticatorAccount account) {
    validateBounds(
      issuer: account.issuer,
      accountName: account.accountName,
      secretKey: account.secretKey,
    );
    final secret = TotpValidator.normalizeSecret(account.secretKey);
    final algorithm = TotpValidator.normalizeAlgorithm(account.algorithm);
    TotpValidator.validateParameters(
      digits: account.digits,
      period: account.period,
    );
    if (secret != account.secretKey.replaceFirst(RegExp(r'=+$'), '') ||
        algorithm != account.algorithm) {
      throw const FormatException('Dữ liệu mã chưa đúng định dạng đồng bộ.');
    }
  }
}
