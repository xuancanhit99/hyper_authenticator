import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/recovery_key_confirmation_dialog.dart';

const _recoveryCode = 'HA1-TEST_ONLY_RECOVERY_CREDENTIAL';

void main() {
  testWidgets(
    'recovery credential không vào semantics và có copy action được gắn nhãn',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpLauncher(tester, textScaler: const TextScaler.linear(2));
      await tester.tap(find.text('Mở dialog'));
      await tester.pumpAndSettle();

      expect(find.text(_recoveryCode), findsOneWidget);
      expect(find.bySemanticsLabel('Recovery key nhạy cảm'), findsOneWidget);
      expect(find.byTooltip('Sao chép recovery key'), findsOneWidget);
      final credentialSemantics = tester
          .getSemantics(find.text(_recoveryCode))
          .getSemanticsData();
      final spokenCredential =
          '${credentialSemantics.label} ${credentialSemantics.value} ${credentialSemantics.hint}';
      expect(spokenCredential, isNot(contains(_recoveryCode)));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      final copyButton = find.widgetWithIcon(IconButton, Icons.copy);
      await tester.ensureVisible(copyButton);
      await tester.pumpAndSettle();
      await tester.tap(copyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(copiedText, _recoveryCode);
      expect(find.text('Đã sao chép recovery key.'), findsOneWidget);

      semantics.dispose();
    },
  );

  testWidgets('xác nhận lưu mới cho phép tiếp tục', (tester) async {
    bool? accepted;
    await _pumpLauncher(tester, onResult: (value) => accepted = value);
    await tester.tap(find.text('Mở dialog'));
    await tester.pumpAndSettle();

    var confirmButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bật encrypted sync'),
    );
    expect(confirmButton.onPressed, isNull);

    await tester.tap(
      find.text('Tôi đã lưu key vào password manager hoặc nơi an toàn.'),
    );
    await tester.pump();
    confirmButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bật encrypted sync'),
    );
    expect(confirmButton.onPressed, isNotNull);

    await tester.tap(find.text('Bật encrypted sync'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('keyboard mặc định focus Hủy để fail-safe', (tester) async {
    bool? accepted;
    await _pumpLauncher(tester, onResult: (value) => accepted = value);
    await tester.tap(find.text('Mở dialog'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(accepted, isFalse);
    expect(find.byType(RecoveryKeyConfirmationDialog), findsNothing);
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<bool>? onResult,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: FilledButton(
          onPressed: () async {
            final result = await showRecoveryKeyConfirmationDialog(
              context,
              recoveryCode: _recoveryCode,
              operation: RecoveryKeyOperation.setup,
            );
            onResult?.call(result);
          },
          child: const Text('Mở dialog'),
        ),
      ),
    ),
  ),
);
