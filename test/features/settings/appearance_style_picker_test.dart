import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/appearance_style_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeCubit> makeCubit({AppStyle? initialStyle}) async {
    SharedPreferences.setMockInitialValues({
      if (initialStyle != null) 'app_style': initialStyle.name,
    });
    return ThemeCubit(await SharedPreferences.getInstance());
  }

  Future<void> pumpPicker(
    WidgetTester tester,
    ThemeCubit cubit, {
    double textScale = 1,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Cài đặt')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Text('Bảo mật'),
                SizedBox(height: 6),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.fingerprint),
                    title: Text('Khóa bằng sinh trắc học'),
                    subtitle: Text('Dùng Face ID hoặc mã khóa thiết bị.'),
                  ),
                ),
                SizedBox(height: 20),
                Text('Hiển thị'),
                SizedBox(height: 6),
                Card(child: AppearanceStylePicker()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Finder> revealPickerRow(WidgetTester tester) async {
    final tile = find.byKey(const Key('appearance-picker-tile'));
    await tester.scrollUntilVisible(
      tile,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return tile;
  }

  Future<void> openSheet(WidgetTester tester) async {
    final tile = await revealPickerRow(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Chọn giao diện'), findsOneWidget);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final rect = tester.getRect(finder);
    final screen = tester.getRect(find.byType(Scaffold));
    expect(rect.top, greaterThanOrEqualTo(screen.top));
    expect(rect.bottom, lessThanOrEqualTo(screen.bottom));
  }

  testWidgets('Settings chỉ hiển thị một hàng giao diện gọn', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = await makeCubit();
    addTearDown(cubit.close);
    await pumpPicker(tester, cubit, textScale: 2);
    await revealPickerRow(tester);

    expect(find.byType(DropdownButton<AppStyle>), findsNothing);
    expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
    expect(find.text('Mặc định · Hệ thống'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('appearance-picker-tile'))).height,
      lessThan(300),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom sheet áp dụng style và mode ngay lập tức', (
    tester,
  ) async {
    final cubit = await makeCubit();
    addTearDown(cubit.close);
    await pumpPicker(tester, cubit);
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('app-style-option-darkCinema')));
    await tester.pumpAndSettle();
    expect(cubit.state.style, AppStyle.darkCinema);

    final darkChoice = find.byKey(const Key('theme-mode-choice-dark'));
    await reveal(tester, darkChoice);
    await tester.tap(darkChoice);
    await tester.pumpAndSettle();
    expect(cubit.state.mode, ThemeMode.dark);

    await tester.tap(find.byKey(const Key('close-appearance-sheet')));
    await tester.pumpAndSettle();
    expect(find.text('Indigo · Tối'), findsOneWidget);
  });

  testWidgets('preview bo kín và mode không chồng checkmark lên icon', (
    tester,
  ) async {
    final cubit = await makeCubit();
    addTearDown(cubit.close);
    await pumpPicker(tester, cubit);
    await openSheet(tester);

    for (final style in AppStyle.values) {
      final preview = find.byKey(Key('app-style-preview-${style.name}'));
      expect(preview, findsOneWidget);
      expect(tester.getSize(preview), const Size(56, 48));

      final clip = find.descendant(
        of: preview,
        matching: find.byType(ClipRRect),
      );
      expect(clip, findsOneWidget);
      final outerRect = tester.getRect(preview);
      final clipRect = tester.getRect(clip);
      expect(clipRect.left, greaterThan(outerRect.left));
      expect(clipRect.top, greaterThan(outerRect.top));
      expect(clipRect.right, lessThan(outerRect.right));
      expect(clipRect.bottom, lessThan(outerRect.bottom));
    }

    for (final mode in ThemeMode.values) {
      final chip = tester.widget<ChoiceChip>(
        find.byKey(Key('theme-mode-choice-${mode.name}')),
      );
      expect(chip.showCheckmark, isFalse);
    }
  });

  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('sheet a11y ${style.name}/${brightness.name} ở 320px 200%', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cubit = await makeCubit(initialStyle: style);
        addTearDown(cubit.close);
        final theme = brightness == Brightness.light
            ? AppTheme.light(style)
            : AppTheme.dark(style);
        await pumpPicker(tester, cubit, textScale: 2, theme: theme);
        await openSheet(tester);

        for (final candidate in AppStyle.values) {
          final option = find.byKey(Key('app-style-option-${candidate.name}'));
          await reveal(tester, option);
          expect(tester.takeException(), isNull);
        }

        for (final mode in ThemeMode.values) {
          await reveal(
            tester,
            find.byKey(Key('theme-mode-choice-${mode.name}')),
          );
        }

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semantics.dispose();
      });
    }
  }
}
