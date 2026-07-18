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
}
