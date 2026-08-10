import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/error/user_facing_failure.dart';

void main() {
  const internalMarker =
      'TEST_ONLY PostgrestException relation=vault.secrets host=internal';

  test('mọi context che message từ server hoặc storage', () {
    for (final context in UserFailureContext.values) {
      final message = userFacingFailureMessage(
        const ServerFailure(internalMarker),
        context: context,
      );

      expect(message, isNot(contains('TEST_ONLY')));
      expect(message, isNot(contains('PostgrestException')));
      expect(message, isNot(contains('vault.secrets')));
      expect(message.trim(), isNotEmpty);
    }
  });

  test('validation do ứng dụng kiểm soát vẫn đưa hướng sửa cụ thể', () {
    const validationMessage = 'Khóa thiết lập không đúng định dạng Base32.';

    expect(
      userFacingFailureMessage(
        const ValidationFailure(validationMessage),
        context: UserFailureContext.addAccount,
      ),
      validationMessage,
    );
  });

  test('không đưa message storage ra lỗi account not found', () {
    final message = userFacingFailureMessage(
      const AccountNotFoundFailure(internalMarker),
      context: UserFailureContext.deleteAccount,
    );

    expect(message, 'Không tìm thấy mã xác thực này trên thiết bị.');
    expect(message, isNot(contains('TEST_ONLY')));
  });
}
