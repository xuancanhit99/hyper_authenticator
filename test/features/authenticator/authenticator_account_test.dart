import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

void main() {
  group('AuthenticatorAccount JSON', () {
    test('round-trip giữ nguyên toàn bộ tham số TOTP', () {
      const account = AuthenticatorAccount(
        id: 'account-id',
        issuer: 'Example',
        accountName: 'user@example.com',
        secretKey: 'JBSWY3DPEHPK3PXP',
        algorithm: 'SHA256',
        digits: 8,
        period: 60,
      );

      expect(AuthenticatorAccount.fromJson(account.toJson()), account);
    });

    test('dữ liệu legacy nhận các giá trị TOTP mặc định', () {
      final account = AuthenticatorAccount.fromJson(const {
        'id': 'legacy-id',
        'issuer': 'Legacy',
        'accountName': 'user@example.com',
        'secretKey': 'JBSWY3DPEHPK3PXP',
      });

      expect(account.algorithm, 'SHA1');
      expect(account.digits, 6);
      expect(account.period, 30);
    });
  });
}
