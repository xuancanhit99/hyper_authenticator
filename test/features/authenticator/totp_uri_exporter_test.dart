import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';

void main() {
  const accounts = [
    AuthenticatorAccount(
      id: 'one',
      issuer: 'TEST_ONLY Standard',
      accountName: 'alice@example.invalid',
      secretKey: 'JBSWY3DPEHPK3PXP',
      algorithm: 'SHA1',
      digits: 6,
      period: 30,
    ),
    AuthenticatorAccount(
      id: 'two',
      issuer: 'TEST_ONLY:Nhóm',
      accountName: 'bob:phone@example.invalid',
      secretKey: 'JBSWY3DPEHPK3PXP',
      algorithm: 'SHA256',
      digits: 8,
      period: 60,
    ),
    AuthenticatorAccount(
      id: 'three',
      issuer: 'TEST_ONLY Unicode',
      accountName: 'người-dùng@example.invalid',
      secretKey: 'JBSWY3DPEHPK3PXP',
      algorithm: 'SHA512',
      digits: 7,
      period: 45,
    ),
  ];

  test('mỗi account thành một URI và parser round-trip đủ semantics', () {
    final parts = TotpUriExporter.export(accounts);

    expect(parts, hasLength(accounts.length));
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final parsed = TotpUriParser.parse(part.uri);
      final source = accounts[index];

      expect(part.index, index);
      expect(part.total, accounts.length);
      expect(parsed.issuer, source.issuer);
      expect(parsed.accountName, source.accountName);
      expect(
        parsed.secretKey.replaceAll('=', ''),
        source.secretKey.replaceAll('=', ''),
      );
      expect(parsed.algorithm, source.algorithm);
      expect(parsed.digits, source.digits);
      expect(parsed.period, source.period);
      expect(part.uri.length, lessThanOrEqualTo(1800));
      expect(part.toString(), contains('uri: [REDACTED]'));
      expect(part.toString(), isNot(contains(source.secretKey)));
    }
  });

  test(
    'fail closed trước khi trả partial list nếu một account không hợp lệ',
    () {
      expect(
        () => TotpUriExporter.export([
          accounts.first,
          const AuthenticatorAccount(
            id: 'invalid',
            issuer: 'TEST_ONLY Invalid',
            accountName: 'invalid@example.invalid',
            secretKey: 'not-valid-1',
          ),
        ]),
        throwsFormatException,
      );
    },
  );

  test('giới hạn account và mật độ QR', () {
    expect(
      () => TotpUriExporter.export(
        List<AuthenticatorAccount>.filled(101, accounts.first),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('100'),
        ),
      ),
    );
    expect(
      () => TotpUriExporter.export([
        AuthenticatorAccount(
          id: 'dense',
          issuer: 'TEST_ONLY ${'I' * 1800}',
          accountName: 'dense@example.invalid',
          secretKey: 'JBSWY3DPEHPK3PXP',
        ),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('quá dài'),
        ),
      ),
    );
  });
}
