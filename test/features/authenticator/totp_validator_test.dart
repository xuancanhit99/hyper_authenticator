import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';

void main() {
  group('TotpValidator', () {
    test('chuẩn hóa Base32 có khoảng trắng và dấu gạch ngang', () {
      expect(
        TotpValidator.normalizeSecret('jbsw y3dp-ehpk 3pxp'),
        'JBSWY3DPEHPK3PXP',
      );
    });

    test('từ chối secret, algorithm, digits và period không hợp lệ', () {
      expect(
        () => TotpValidator.normalizeSecret('INVALID_0189'),
        throwsFormatException,
      );
      expect(
        () => TotpValidator.normalizeAlgorithm('MD5'),
        throwsFormatException,
      );
      expect(
        () => TotpValidator.validateParameters(digits: 5, period: 30),
        throwsFormatException,
      );
      expect(
        () => TotpValidator.validateParameters(digits: 6, period: 0),
        throwsFormatException,
      );
    });
  });
}
