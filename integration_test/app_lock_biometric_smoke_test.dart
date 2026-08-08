import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowAppLockTest = bool.fromEnvironment('ALLOW_DEVICE_APP_LOCK_TEST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'app lock fail closed và mở khóa bằng biometric hệ điều hành',
    (tester) async {
      expect(
        _allowAppLockTest,
        isTrue,
        reason:
            'Chỉ chạy test app lock trên simulator/AVD sạch qua harness có opt-in.',
      );

      final preferences = await SharedPreferences.getInstance();

      try {
        await preferences.setBool('biometric_enabled', false);
        await app.main();
        await _pumpUntil(tester, find.byKey(MainNavigationPage.settingsTabKey));

        await tester.tap(find.byKey(MainNavigationPage.settingsTabKey).last);
        await _pumpUntil(tester, find.text('Cài đặt'));

        final biometricTile = find.widgetWithText(
          SwitchListTile,
          'Khóa bằng sinh trắc học',
        );
        await _pumpUntil(tester, biometricTile);
        expect(tester.widget<SwitchListTile>(biometricTile).value, isFalse);

        await tester.tap(biometricTile);
        await _waitForPreference(preferences, expected: true);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<SwitchListTile>(biometricTile).value, isTrue);
        _phase('preference-enabled');

        await _backgroundAndResume(tester);
        await _pumpUntil(tester, find.text('Ứng dụng đang được khóa'));
        _phase('awaiting-biometric-match');
        await _pumpUntil(
          tester,
          find.text('Cài đặt'),
          timeout: const Duration(minutes: 2),
        );
        await _waitForStableResumed(tester);
        _phase('biometric-unlock-verified');

        await _backgroundAndResume(tester);
        await _pumpUntil(tester, find.text('Ứng dụng đang được khóa'));
        _phase('awaiting-biometric-nonmatch');
        await _waitForStableResumed(tester);
        expect(find.text('Ứng dụng đang được khóa'), findsOneWidget);
        _phase('nonmatch-remains-locked');

        final unlockButton = find
            .widgetWithText(FilledButton, 'Mở khóa')
            .hitTestable();
        await _pumpUntil(tester, unlockButton);
        await tester.tap(unlockButton);
        await tester.pump(const Duration(milliseconds: 200));
        _phase('awaiting-biometric-match-after-nonmatch');
        await _pumpUntil(
          tester,
          find.text('Cài đặt'),
          timeout: const Duration(minutes: 2),
        );
        await _waitForStableResumed(tester);
        _phase('retry-unlock-verified');

        final enabledTile = find.widgetWithText(
          SwitchListTile,
          'Khóa bằng sinh trắc học',
        );
        await _pumpUntil(tester, enabledTile);
        await tester.tap(enabledTile);
        await _waitForPreference(preferences, expected: false);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<SwitchListTile>(enabledTile).value, isFalse);
        _phase('preference-disabled');

        await _backgroundAndResume(tester);
        await _pumpUntil(tester, find.text('Cài đặt'));
        expect(find.text('Ứng dụng đang được khóa'), findsNothing);
        _phase('disabled-lock-not-applied');
      } finally {
        await preferences.setBool('biometric_enabled', false);
        _phase('finally-preference-cleanup-complete');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  await _waitForStableResumed(tester);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump(const Duration(milliseconds: 100));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  await tester.pump(const Duration(milliseconds: 100));

  // Không pump khi paused: iOS có thể dừng scheduler cho tới khi resumed.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _waitForStableResumed(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  DateTime? resumedSince;

  while (true) {
    await tester.pump(const Duration(milliseconds: 100));
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      resumedSince ??= DateTime.now();
      if (DateTime.now().difference(resumedSince) >=
          const Duration(milliseconds: 500)) {
        return;
      }
    } else {
      resumedSince = null;
    }

    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timeout khi chờ lifecycle ổn định ở resumed.');
    }
  }
}

Future<void> _waitForPreference(
  SharedPreferences preferences, {
  required bool expected,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (preferences.getBool('biometric_enabled') != expected) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(
        'Timeout khi chờ biometric_enabled=$expected được persist.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
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

void _phase(String name) {
  debugPrint('APP_LOCK_DEVICE_PHASE=$name');
}
