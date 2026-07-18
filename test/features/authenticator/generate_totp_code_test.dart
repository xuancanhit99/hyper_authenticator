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
}
