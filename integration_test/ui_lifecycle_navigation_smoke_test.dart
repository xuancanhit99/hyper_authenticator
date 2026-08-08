import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bottom navigation phản hồi qua nhiều chuỗi background/resume',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('biometric_enabled', false);

      await app.main();
      await _pumpUntil(tester, find.byKey(MainNavigationPage.accountsTabKey));

      for (var cycle = 0; cycle < 3; cycle++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(milliseconds: 100));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump(const Duration(milliseconds: 100));

        // iOS dừng frame scheduling ở `paused`; phát resume sequence đồng bộ
        // trước lần pump kế tiếp để integration runner không tự deadlock.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 200));

        await _pumpUntil(tester, find.byKey(MainNavigationPage.settingsTabKey));
        await tester.tap(find.byKey(MainNavigationPage.settingsTabKey).last);
        await _pumpUntil(tester, find.text('Cài đặt'));

        await tester.tap(find.byKey(MainNavigationPage.accountsTabKey).last);
        await _pumpUntil(tester, find.text('Mã xác thực'));
      }

      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timeout khi chờ widget: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}
