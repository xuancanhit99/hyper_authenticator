import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';

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
}
