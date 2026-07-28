import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/platform/system_ui_interaction_guard.dart';

void main() {
  test(
    'active chỉ true trong thời gian system UI operation đang chờ',
    () async {
      final completion = Completer<String>();

      final operation = SystemUiInteractionGuard.run(() => completion.future);
      expect(SystemUiInteractionGuard.isActive, isTrue);

      completion.complete('done');
      expect(await operation, 'done');
      expect(SystemUiInteractionGuard.isActive, isFalse);
    },
  );

  test('luôn giải phóng guard khi system UI operation lỗi', () async {
    await expectLater(
      SystemUiInteractionGuard.run<void>(
        () => Future<void>.error(StateError('TEST_ONLY')),
      ),
      throwsStateError,
    );

    expect(SystemUiInteractionGuard.isActive, isFalse);
  });
}
