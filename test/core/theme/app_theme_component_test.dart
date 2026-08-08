import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/constants/app_colors.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

void main() {
  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    final brightness = theme.brightness.name;

    test('$brightness card clip ink theo đúng bo góc', () {
      expect(theme.cardTheme.clipBehavior, Clip.antiAlias);
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
    });

    test('$brightness button giữ padding ngang và tap target', () {
      for (final style in [
        theme.outlinedButtonTheme.style,
        theme.elevatedButtonTheme.style,
        theme.filledButtonTheme.style,
      ]) {
        expect(
          style?.minimumSize?.resolve(const <WidgetState>{}),
          const Size(64, 48),
        );
        expect(
          style?.padding?.resolve(const <WidgetState>{}),
          const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        );
      }

      final expectedPrimary = theme.brightness == Brightness.light
          ? AppColors.primaryLight
          : AppColors.primaryDark;
      expect(
        theme.outlinedButtonTheme.style?.foregroundColor?.resolve(
          const <WidgetState>{},
        ),
        expectedPrimary,
      );
      expect(
        theme.elevatedButtonTheme.style?.backgroundColor?.resolve(
          const <WidgetState>{},
        ),
        expectedPrimary,
      );

      final focusedBorder =
          theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(theme.inputDecorationTheme.prefixIconColor, expectedPrimary);
      expect(
        theme.inputDecorationTheme.floatingLabelStyle?.color,
        expectedPrimary,
      );
      expect(focusedBorder.borderSide.color, expectedPrimary);
    });
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
