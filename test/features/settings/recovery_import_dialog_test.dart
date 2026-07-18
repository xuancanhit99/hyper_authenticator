import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/recovery_import_dialog.dart';

void main() {
  testWidgets('đóng dialog an toàn sau khi trả recovery key', (tester) async {
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                submitted = await showRecoveryImportDialog(context);
              },
              child: const Text('Mở dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  HA1-test-value  ');
    await tester.pump();
    await tester.tap(find.text('Khôi phục'));
    await tester.pumpAndSettle();

    expect(submitted, '  HA1-test-value  ');
    expect(find.byType(RecoveryImportDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hủy dialog không trả recovery key', (tester) async {
    String? submitted = 'unchanged';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                submitted = await showRecoveryImportDialog(context);
              },
              child: const Text('Mở dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    expect(submitted, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'field có accessible name, autofocus, che key và submit bằng keyboard',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const recoveryCode = 'HA1-TEST_ONLY_RECOVERY_CREDENTIAL';
      String? submitted;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  submitted = await showRecoveryImportDialog(context);
                },
                child: const Text('Mở dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở dialog'));
      await tester.pumpAndSettle();

      final restoreButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Khôi phục'),
      );
      expect(restoreButton.onPressed, isNull);
      final editableText = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(editableText.focusNode.hasFocus, isTrue);

      await tester.enterText(find.byType(TextField), recoveryCode);
      await tester.pump();
      final fieldSemantics = tester
          .getSemantics(find.byType(TextField))
          .getSemanticsData();
      final spokenContent =
          '${fieldSemantics.label} ${fieldSemantics.value} ${fieldSemantics.hint}';
      expect(find.bySemanticsLabel(RegExp('Recovery key')), findsOneWidget);
      expect(spokenContent, isNot(contains(recoveryCode)));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submitted, recoveryCode);
      expect(find.byType(RecoveryImportDialog), findsNothing);
      semantics.dispose();
    },
  );
}
