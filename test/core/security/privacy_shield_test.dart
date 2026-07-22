import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('che semantics và interaction ở mọi lifecycle ngoài resumed', (
    tester,
  ) async {
    const sensitiveLabel = 'TEST_ONLY OTP 123 456';
    const actionKey = ValueKey<String>('sensitive-action');
    var actionCount = 0;
    final actionFocusNode = FocusNode();
    addTearDown(actionFocusNode.dispose);
    final semantics = tester.ensureSemantics();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyShield(
          child: Scaffold(
            body: Center(
              child: TextButton(
                key: actionKey,
                autofocus: true,
                focusNode: actionFocusNode,
                onPressed: () => actionCount += 1,
                child: const Text(sensitiveLabel),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(privacyShieldOverlayKey), findsNothing);
    expect(find.semantics.byLabel(sensitiveLabel), findsOne);
    expect(actionFocusNode.hasFocus, isTrue);
    await tester.tap(find.byKey(actionKey));
    expect(actionCount, 1);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();

      expect(
        find.byKey(privacyShieldOverlayKey),
        findsOneWidget,
        reason: 'Privacy shield phải hiển thị ở trạng thái $state.',
      );
      final overlay = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(privacyShieldOverlayKey),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(overlay.color.a, 1);
      expect(find.semantics.byLabel(sensitiveLabel), findsNothing);
      expect(find.semantics.byLabel(privacyShieldSemanticsLabel), findsOne);
      expect(actionFocusNode.hasFocus, isFalse);
      await tester.tap(find.byKey(actionKey), warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(actionFocusNode.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(actionCount, 1);
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byKey(privacyShieldOverlayKey), findsNothing);
    expect(find.semantics.byLabel(sensitiveLabel), findsOne);
    await tester.tap(find.byKey(actionKey));
    expect(actionCount, 2);
    semantics.dispose();
  });

  testWidgets('không khóa bootstrap trước lifecycle signal', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PrivacyShield(
          child: Scaffold(body: Text('TEST_ONLY bootstrap ready')),
        ),
      ),
    );

    expect(find.byKey(privacyShieldOverlayKey), findsNothing);
    expect(find.text('TEST_ONLY bootstrap ready'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byKey(privacyShieldOverlayKey), findsOneWidget);
  });

  testWidgets('giao diện shield responsive và opaque ở light/dark theme', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const PrivacyShield(
              child: Scaffold(body: Text('TEST_ONLY sensitive content')),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();

      expect(find.byKey(privacyShieldOverlayKey), findsOneWidget);
      expect(find.text('Nội dung đang được bảo vệ'), findsOneWidget);
      expect(find.text('Quay lại ứng dụng để tiếp tục.'), findsOneWidget);
      final background = tester.widget<ColoredBox>(
        find.byKey(privacyShieldBackgroundKey),
      );
      expect(background.color.a, 1);
      expect(
        find.semantics.byLabel('TEST_ONLY sensitive content'),
        findsNothing,
      );
      expect(find.semantics.byLabel(privacyShieldSemanticsLabel), findsOne);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(tester.takeException(), isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }
    semantics.dispose();
  });
}
