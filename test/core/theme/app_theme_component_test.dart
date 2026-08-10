import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

void main() {
  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.light
          ? AppTheme.light(style)
          : AppTheme.dark(style);
      final palette = AppStylePalette.of(style, brightness);
      final variant = '${style.name}/${brightness.name}';

      test('$variant dùng geometry token nhất quán', () {
        expect(theme.cardTheme.clipBehavior, Clip.antiAlias);
        expect(theme.cardTheme.margin, EdgeInsets.zero);
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
        expect(
          cardShape.borderRadius,
          BorderRadius.circular(palette.cardRadius),
        );

        for (final buttonStyle in [
          theme.outlinedButtonTheme.style,
          theme.elevatedButtonTheme.style,
          theme.filledButtonTheme.style,
        ]) {
          expect(
            buttonStyle?.minimumSize?.resolve(const <WidgetState>{}),
            const Size(64, 48),
          );
          expect(
            buttonStyle?.padding?.resolve(const <WidgetState>{}),
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          );
          final shape =
              buttonStyle?.shape?.resolve(const <WidgetState>{})
                  as RoundedRectangleBorder;
          expect(
            shape.borderRadius,
            BorderRadius.circular(palette.controlRadius),
          );
        }

        final inputBorder =
            theme.inputDecorationTheme.border! as OutlineInputBorder;
        final focusedBorder =
            theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
        expect(
          inputBorder.borderRadius,
          BorderRadius.circular(palette.controlRadius),
        );
        expect(focusedBorder.borderRadius, inputBorder.borderRadius);
        expect(theme.inputDecorationTheme.prefixIconColor, palette.primary);
        expect(
          theme.inputDecorationTheme.floatingLabelStyle?.color,
          palette.primary,
        );
        expect(focusedBorder.borderSide.color, palette.primary);

        final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
        expect(
          dialogShape.borderRadius,
          BorderRadius.circular(palette.dialogRadius),
        );
        final sheetShape =
            theme.bottomSheetTheme.shape as RoundedRectangleBorder;
        expect(
          sheetShape.borderRadius,
          BorderRadius.vertical(top: Radius.circular(palette.sheetRadius)),
        );
        expect(theme.dividerTheme.thickness, 1);
        expect(theme.dividerTheme.space, 1);

        expect(
          theme.outlinedButtonTheme.style?.foregroundColor?.resolve(
            const <WidgetState>{},
          ),
          palette.primary,
        );
        expect(
          theme.elevatedButtonTheme.style?.backgroundColor?.resolve(
            const <WidgetState>{},
          ),
          palette.primary,
        );
      });
    }
  }

  testWidgets('pressed overlay của tile được clip trong card bo tròn', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: Card(
                key: Key('interactive-card'),
                child: ListTile(
                  title: Text('Bảo mật tài khoản nâng cao'),
                  onTap: _noop,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const Key('interactive-card')),
        matching: find.byType(Material),
      ),
    );
    expect(material.clipBehavior, Clip.antiAlias);
    expect(material.shape, isA<RoundedRectangleBorder>());

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Bảo mật tài khoản nâng cao')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await gesture.up();
  });
}

void _noop() {}
