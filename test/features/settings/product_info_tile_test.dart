import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/product_info_tile.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required ThemeData theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [Card(child: ProductInfoTile())],
          ),
        ),
      ),
    );
  }

  testWidgets('hàng giới thiệu gọn và mở thông tin sản phẩm', (tester) async {
    await pumpTile(tester, theme: AppTheme.lightTheme);

    expect(find.text('Giới thiệu'), findsOneWidget);
    expect(
      find.text('Hyper Authenticator · Phiên bản 1.1.2 (16)'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('product-info-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Dùng không cần tài khoản'), findsOneWidget);
    expect(find.text('Đồng bộ khi đăng nhập'), findsOneWidget);
    expect(find.text('Bảo vệ dữ liệu'), findsOneWidget);
    expect(
      find.byKey(const Key('open-source-licenses-action')),
      findsOneWidget,
    );
    expect(find.textContaining('Supabase'), findsNothing);
    expect(find.textContaining('E2EE'), findsNothing);
    expect(tester.takeException(), isNull);

    final licenses = find.byKey(const Key('open-source-licenses-action'));
    await tester.ensureVisible(licenses);
    await tester.pumpAndSettle();
    await tester.tap(licenses);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    testWidgets('sheet responsive và accessible ở 320px 200%', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      await pumpTile(tester, theme: theme, textScale: 2);
      await tester.tap(find.byKey(const Key('product-info-tile')));
      await tester.pumpAndSettle();

      final action = find.byKey(const Key('open-source-licenses-action'));
      await tester.scrollUntilVisible(
        action,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    });
  }
}
