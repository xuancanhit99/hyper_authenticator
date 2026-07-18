import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/sync_conflict_resolution_dialog.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('conflict dialog pass accessibility/contrast ${themeMode.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? accepted;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
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
                  accepted = await showSyncConflictResolutionDialog(
                    context,
                    title: 'Thay local vault bằng bản cloud?',
                    message:
                        'Snapshot local hợp lệ hiện tại vẫn có generation rollback.',
                    action: 'Dùng cloud',
                  );
                },
                child: const Text('Mở dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở dialog'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Thay local vault bằng bản cloud?'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Hủy'), findsOneWidget);
      expect(find.bySemanticsLabel('Dùng cloud'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(accepted, isFalse);
      expect(find.byType(SyncConflictResolutionDialog), findsNothing);
      semantics.dispose();
    });
  }
}
