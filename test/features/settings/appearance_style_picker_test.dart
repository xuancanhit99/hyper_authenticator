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

  /// Fixture khớp composition Settings thật: AppBar, ListView padding 16 và
  /// card đứng trước/sau card Giao diện để kiểm tra đúng scroll viewport.
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
                    title: Text('Backup file mã hóa'),
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

  Future<void> scrollChipsIntoViewport(WidgetTester tester) async {
    await centerInViewport(
      tester,
      find.byKey(const Key('theme-mode-selector')),
    );
  }

  void expectFullyVisible(WidgetTester tester, Finder finder, String reason) {
    final rect = tester.getRect(finder);
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final viewportBottom = tester.getRect(find.byType(Scaffold)).bottom;
    expect(rect.top, greaterThan(appBarBottom + 8), reason: reason);
    expect(rect.bottom, lessThan(viewportBottom - 8), reason: reason);
  }

  void expectChipsFullyVisible(WidgetTester tester) {
    for (final mode in ThemeMode.values) {
      expectFullyVisible(
        tester,
        find.byKey(Key('theme-mode-${mode.name}')),
        mode.name,
      );
    }
  }

  testWidgets('320px + text scale 200% không overflow và chip không nổ dọc', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = await makeCubit();
    await pumpPicker(tester, cubit, textScale: 2);

    expect(tester.takeException(), isNull);
    for (final label in ['Security Minimal', 'OLED Dark', 'Dark Cinema']) {
      expect(find.text(label), findsOneWidget);
    }
    await scrollChipsIntoViewport(tester);
    // Regression SegmentedButton: segment hẹp từng làm label wrap gần như
    // từng ký tự và đẩy card lên ~2.700px. Invariant là từng label/chip không
    // nổ chiều dọc; chiều cao tổng phụ thuộc mô tả wrap hợp lệ nên không phải
    // invariant.
    for (final label in ['Hệ thống', 'Sáng', 'Tối']) {
      expect(find.text(label), findsOneWidget);
      expect(tester.getSize(find.text(label)).height, lessThan(60));
    }
    for (final chip in find.byType(ChoiceChip).evaluate()) {
      expect(tester.getSize(find.byWidget(chip.widget)).height, lessThan(120));
    }
  });

  // Sweep a11y đủ 6 theme thực tế; style đang chọn trùng theme để cover cả
  // trạng thái selected của từng tile.
  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('picker a11y ${style.name}/${brightness.name} ở 320px/200%', (
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

        // Viewport đầu: AppBar + card sinh trắc học + đầu card Giao diện.
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        // Đưa từng style tile vào giữa viewport trước khi chạy guideline.
        // Mỗi test có style hiện hành trùng palette, nên vòng này cover đúng
        // một selected tile và hai unselected tile trên cả 6 theme.
        for (final candidate in AppStyle.values) {
          final tile = find.byKey(Key('app-style-${candidate.name}'));
          await centerInViewport(tester, tile);
          expectFullyVisible(tester, tile, candidate.name);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        }

        // Chip nằm trọn trong viewport (không dính rìa) rồi mới đánh giá —
        // cover chip selected (mode hiện tại) lẫn unselected.
        await scrollChipsIntoViewport(tester);
        expectChipsFullyVisible(tester);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

        // Đổi selection để chip khác thành selected rồi đánh giá lại.
        await tester.tap(find.byKey(const Key('theme-mode-dark')));
        await tester.pumpAndSettle();
        expectChipsFullyVisible(tester);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semantics.dispose();
      });
    }
  }

  testWidgets('chọn style và mode cập nhật ThemeCubit', (tester) async {
    final cubit = await makeCubit();
    await pumpPicker(tester, cubit);

    await tester.ensureVisible(find.byKey(const Key('app-style-oledDark')));
    await tester.tap(find.byKey(const Key('app-style-oledDark')));
    await tester.pumpAndSettle();
    expect(cubit.state.style, AppStyle.oledDark);

    await tester.ensureVisible(find.byKey(const Key('theme-mode-dark')));
    await tester.tap(find.byKey(const Key('theme-mode-dark')));
    await tester.pumpAndSettle();
    expect(cubit.state.mode, ThemeMode.dark);
  });
}
