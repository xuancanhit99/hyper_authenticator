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
                Card(
                  child: ListTile(
                    leading: Icon(Icons.fingerprint),
                    title: Text('Khóa bằng sinh trắc học'),
                    subtitle: Text('Dùng Face ID hoặc mã khóa thiết bị.'),
                  ),
                ),
                SizedBox(height: 12),
                Card(child: AppearanceStylePicker()),
                SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.folder_zip_outlined),
                    title: Text('Nhập và xuất QR'),
                    subtitle: Text('Portable offline, không cần Supabase.'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> centerInViewport(WidgetTester tester, Finder finder) async {
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final viewportBottom = tester.getRect(find.byType(Scaffold)).bottom;
    const margin = 12.0;
    final availableHeight = viewportBottom - appBarBottom - (margin * 2);
    final scrollable = find.byType(Scrollable).first;
    for (var attempt = 0; attempt < 20; attempt++) {
      final target = tester.getRect(finder);
      expect(target.height, lessThan(availableHeight));
      final desiredTop =
          appBarBottom + margin + ((availableHeight - target.height) / 2);
      final delta = (desiredTop - target.top).clamp(-240.0, 240.0);
      if (delta.abs() < 1) break;
      await tester.drag(scrollable, Offset(0, delta));
      await tester.pumpAndSettle();
    }
  }

  void expectFullyVisible(WidgetTester tester, Finder finder, String reason) {
    final rect = tester.getRect(finder);
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final viewportBottom = tester.getRect(find.byType(Scaffold)).bottom;
    expect(rect.top, greaterThan(appBarBottom + 8), reason: reason);
    expect(rect.bottom, lessThan(viewportBottom - 8), reason: reason);
  }

  testWidgets('dropdown gọn và không overflow ở 320px + text scale 200%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = await makeCubit();
    await pumpPicker(tester, cubit, textScale: 2);

    expect(find.byType(RadioListTile<AppStyle>), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const Key('app-style-dropdown')), findsOneWidget);
    expect(find.byKey(const Key('theme-mode-dropdown')), findsOneWidget);
    final pickerCard = find
        .ancestor(
          of: find.byType(AppearanceStylePicker),
          matching: find.byType(Card),
        )
        .first;
    expect(tester.getSize(pickerCard).height, lessThan(440));
    expect(tester.takeException(), isNull);

    await centerInViewport(tester, find.byKey(const Key('app-style-dropdown')));
    await tester.tap(find.byKey(const Key('app-style-dropdown')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('app-style-option-oledDark')).last);
    await tester.pumpAndSettle();
    expect(cubit.state.style, AppStyle.oledDark);

    await centerInViewport(
      tester,
      find.byKey(const Key('theme-mode-dropdown')),
    );
    await tester.tap(find.byKey(const Key('theme-mode-dropdown')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('theme-mode-option-dark')).last);
    await tester.pumpAndSettle();
    expect(cubit.state.mode, ThemeMode.dark);
  });

  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('dropdown a11y ${style.name}/${brightness.name}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cubit = await makeCubit(initialStyle: style);
        final theme = brightness == Brightness.light
            ? AppTheme.light(style)
            : AppTheme.dark(style);
        await pumpPicker(tester, cubit, textScale: 2, theme: theme);

        for (final key in const [
          Key('app-style-dropdown'),
          Key('theme-mode-dropdown'),
        ]) {
          final dropdown = find.byKey(key);
          await centerInViewport(tester, dropdown);
          expectFullyVisible(tester, dropdown, key.toString());
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        }
        semantics.dispose();
      });
    }
  }

  testWidgets('chọn style và mode cập nhật ThemeCubit', (tester) async {
    final cubit = await makeCubit();
    await pumpPicker(tester, cubit);

    await tester.ensureVisible(find.byKey(const Key('app-style-dropdown')));
    await tester.tap(find.byKey(const Key('app-style-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-style-option-darkCinema')).last);
    await tester.pumpAndSettle();
    expect(cubit.state.style, AppStyle.darkCinema);

    await tester.ensureVisible(find.byKey(const Key('theme-mode-dropdown')));
    await tester.tap(find.byKey(const Key('theme-mode-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-mode-option-dark')).last);
    await tester.pumpAndSettle();
    expect(cubit.state.mode, ThemeMode.dark);
  });
}
