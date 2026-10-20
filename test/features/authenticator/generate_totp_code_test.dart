import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/generate_totp_code.dart';

void main() {
  test('tạo mã SHA1 đúng vector RFC 6238 tại giây 59', () async {
    final result = await GenerateTotpCode()(
      const GenerateTotpCodeParams(
        secretKey: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        algorithm: 'SHA1',
        digits: 8,
        period: 30,
        timestampMilliseconds: 59000,
      ),
    );

    expect(result.getOrElse((_) => ''), '94287082');
  });

  test('mọi vector SHA1/256/512 của RFC 6238 vẫn đúng', () async {
    const times = [
      59,
      1111111109,
      1111111111,
      1234567890,
      2000000000,
      20000000000,
    ];
    const vectors = [
      (
        'SHA1',
        '12345678901234567890',
        [
          '94287082',
          '07081804',
          '14050471',
          '89005924',
          '69279037',
          '65353130',
        ],
      ),
      (
        'SHA256',
        '12345678901234567890123456789012',
        [
          '46119246',
          '68084774',
          '67062674',
          '91819424',
          '90698825',
          '77737706',
        ],
      ),
      (
        'SHA512',
        '1234567890123456789012345678901234567890123456789012345678901234',
        [
          '90693936',
          '25091201',
          '99943326',
          '93441116',
          '38618901',
          '47863826',
        ],
      ),
    ];
    for (final (algorithm, asciiKey, expected) in vectors) {
      final secret = base32.encode(Uint8List.fromList(ascii.encode(asciiKey)));
      for (var i = 0; i < times.length; i++) {
        final result = await GenerateTotpCode()(
          GenerateTotpCodeParams(
            secretKey: secret,
            algorithm: algorithm,
            digits: 8,
            period: 30,
            timestampMilliseconds: times[i] * 1000,
          ),
        );
        expect(result.getOrElse((_) => ''), expected[i]);
      }
    }
  });

  test(
    'key ngắn padded/unpadded dùng đúng byte HMAC và không bị cắt',
    () async {
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
        for (final input in [
          canonical,
          padded,
          ' ${canonical.toLowerCase()}-\n',
        ]) {
          final result = await GenerateTotpCode()(
            GenerateTotpCodeParams(
              secretKey: input,
              algorithm: 'SHA1',
              digits: 6,
              period: 30,
              timestampMilliseconds: 59000,
            ),
          );
          expect(result.getOrElse((_) => ''), await _referenceCode(bytes));
        }
      }
    },
  );

  test('key lỗi đã lưu không được sinh OTP của key rỗng hoặc bị cắt', () async {
    for (final input in ['A', 'ABC', 'ABCDEF', 'AAAAAAAAA', 'MY=', 'MZ']) {
      final result = await GenerateTotpCode()(
        GenerateTotpCodeParams(
          secretKey: input,
          algorithm: 'SHA1',
          digits: 6,
          period: 30,
          timestampMilliseconds: 59000,
        ),
      );
      expect(result.isLeft(), isTrue);
    }
  });
}

Future<String> _referenceCode(List<int> keyBytes) async {
  // At second 59 with period 30, counter = 1. Decode is deliberately absent:
  // this reference HMAC uses the known RFC 4648 bytes, independently of OTP.
  final digest = (await Hmac.sha1().calculateMac([
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
  ], secretKey: SecretKey(keyBytes))).bytes;
  final offset = digest.last & 15;
  final binary =
      ((digest[offset] & 127) << 24) |
      (digest[offset + 1] << 16) |
      (digest[offset + 2] << 8) |
      digest[offset + 3];
  return (binary % 1000000).toString().padLeft(6, '0');
}
