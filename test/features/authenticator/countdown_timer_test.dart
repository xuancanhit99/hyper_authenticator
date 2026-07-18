import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart';

void main() {
  group('TotpTimeWindow', () {
    test('tính time step và thời gian còn lại theo từng period', () {
      const epochSeconds = 121;
      final expected = <int, (int, int)>{
        15: (8, 14),
        30: (4, 29),
        45: (2, 14),
        60: (2, 59),
      };

      for (final entry in expected.entries) {
        final window = TotpTimeWindow.fromEpochSeconds(
          epochSeconds: epochSeconds,
          periodSeconds: entry.key,
        );

        expect(window.timeStep, entry.value.$1, reason: 'period ${entry.key}');
        expect(
          window.secondsRemaining,
          entry.value.$2,
          reason: 'period ${entry.key}',
        );
      }
    });

    test('trả về toàn bộ period tại đúng ranh giới time step', () {
      final window = TotpTimeWindow.fromEpochSeconds(
        epochSeconds: 180,
        periodSeconds: 60,
      );

      expect(window.timeStep, 3);
      expect(window.secondsRemaining, 60);
    });

    test('từ chối period không hợp lệ', () {
      expect(
        () =>
            TotpTimeWindow.fromEpochSeconds(epochSeconds: 0, periodSeconds: 0),
        throwsArgumentError,
      );
    });
  });

  testWidgets('countdown công bố đúng period cho accessibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CircularCountdownTimer(secondsRemaining: 29, periodSeconds: 60),
      ),
    );

    expect(
      find.bySemanticsLabel('29 seconds remaining of a 60-second period'),
      findsOneWidget,
    );
  });
}
