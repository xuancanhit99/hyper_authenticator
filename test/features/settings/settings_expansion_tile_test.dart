import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/settings_expansion_tile.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'advanced Settings disclosure không tự vẽ divider ${themeMode.name}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const Scaffold(
              body: Card(
                child: SettingsExpansionTile(
                  title: Text('Bảo mật nâng cao'),
                  subtitle: Text('Mô tả'),
                  children: [Text('Nội dung mở rộng')],
                ),
              ),
            ),
          ),
        );

        final expansionTile = tester.widget<ExpansionTile>(
          find.byType(ExpansionTile),
        );
        expect(expansionTile.shape, const Border());
        expect(expansionTile.collapsedShape, const Border());

        await tester.tap(find.text('Bảo mật nâng cao'));
        await tester.pumpAndSettle();

        expect(find.text('Nội dung mở rộng'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
