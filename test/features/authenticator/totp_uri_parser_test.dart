import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';

void main() {
  group('TotpUriParser', () {
    test('đọc đầy đủ otpauth URI', () {
      final account = TotpUriParser.parse(
        'otpauth://totp/Example:user%40example.com'
        '?secret=jbswy3dpehpk3pxp&issuer=Example'
        '&algorithm=SHA256&digits=8&period=60',
      );

      expect(account.issuer, 'Example');
      expect(account.accountName, 'user@example.com');
      expect(account.secretKey, 'JBSWY3DPEHPK3PXP');
      expect(account.algorithm, 'SHA256');
      expect(account.digits, 8);
      expect(account.period, 60);
    });

    test('lấy issuer từ label khi query không có issuer', () {
      final account = TotpUriParser.parse(
        'otpauth://totp/Example:user?secret=JBSWY3DPEHPK3PXP',
      );

      expect(account.issuer, 'Example');
      expect(account.accountName, 'user');
    });

    test(
      'issuer và account name chứa dấu hai chấm vẫn round-trip chính xác',
      () {
        final account = TotpUriParser.parse(
          'otpauth://totp/TEST_ONLY%3ANh%C3%B3m%3Auser%3Aphone'
          '?secret=JBSWY3DPEHPK3PXP&issuer=TEST_ONLY%3ANh%C3%B3m',
        );

        expect(account.issuer, 'TEST_ONLY:Nhóm');
        expect(account.accountName, 'user:phone');
      },
    );

    test('từ chối query bảo mật bị lặp và URI vượt giới hạn', () {
      expect(
        () => TotpUriParser.parse(
          'otpauth://totp/Example:user'
          '?secret=JBSWY3DPEHPK3PXP&secret=JBSWY3DPEHPK3PXP'
          '&issuer=Example',
        ),
        throwsFormatException,
      );
      expect(
        () => TotpUriParser.parse(
          'otpauth://totp/Example:${'x' * (16 * 1024)}'
          '?secret=JBSWY3DPEHPK3PXP&issuer=Example',
        ),
        throwsFormatException,
      );
    });

    test('từ chối HOTP và secret không phải Base32', () {
      expect(
        () => TotpUriParser.parse(
          'otpauth://hotp/Example:user?secret=JBSWY3DPEHPK3PXP',
        ),
        throwsFormatException,
      );
      expect(
        () => TotpUriParser.parse(
          'otpauth://totp/Example:user?secret=not-valid-1',
        ),
        throwsFormatException,
      );
    });
  });
}
