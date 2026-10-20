import 'package:base32/base32.dart';
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

    test('canonical unpadded và padded giữ đủ từng byte RFC 4648', () {
      const vectors = [
        ('AA', 'AA======', [0]),
        ('MY', 'MY======', [102]),
        ('MZXQ', 'MZXQ====', [102, 111]),
        ('MZXW6', 'MZXW6===', [102, 111, 111]),
        ('MZXW6YQ', 'MZXW6YQ=', [102, 111, 111, 98]),
        ('MZXW6YTB', 'MZXW6YTB', [102, 111, 111, 98, 97]),
        ('MZXW6YTBOI', 'MZXW6YTBOI======', [102, 111, 111, 98, 97, 114]),
      ];
      for (final (canonical, padded, bytes) in vectors) {
        for (final input in [canonical, padded]) {
          final normalized = TotpValidator.normalizeSecret(input);
          expect(normalized, canonical);
          expect(base32.decode(normalized), bytes);
        }
      }
      expect(TotpValidator.normalizeSecret(' m y ==-====\n'), 'MY');
    });

    test('từ chối residual length, padding và pad bits không hợp lệ', () {
      const malformed = [
        '',
        ' -\n',
        '======',
        'A',
        'ABC',
        'ABCDEF',
        'AAAAAAAAA',
        'A=======',
        'MY=',
        'MY=====',
        'MY=======',
        'MZXQ===',
        'MZXW6====',
        'MZXW6YQ==',
        'MZXW6YTB=',
        'M=Y',
        'MZ',
        'MZ======',
        'MZXR',
        'MZXW7',
        'MZXW6YR',
      ];
      for (final input in malformed) {
        expect(
          () => TotpValidator.normalizeSecret(input),
          throwsFormatException,
        );
      }
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
      expect(
        () => TotpValidator.validateParameters(digits: 6, period: 301),
        throwsFormatException,
      );
    });
  });
}
