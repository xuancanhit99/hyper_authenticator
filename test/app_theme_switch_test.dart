import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/app.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/app_style_tokens.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Store treo mọi lượt ghi cho đến khi test chủ động complete — dùng để chứng
/// minh theme áp dụng ngay trong khi persistence còn đang chờ.
class _BlockingStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _data = {};
  final List<Completer<bool>> pendingWrites = [];

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.of(_data);

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final completer = Completer<bool>();
    pendingWrites.add(completer);
    return completer.future.then((accepted) {
      if (accepted) _data[key] = value;
      return accepted;
    });
  }
}

void main() {
  testWidgets('đổi mode/style trong ThemeCubit re-theme MyApp ngay lập tức', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(preferences);
    addTearDown(cubit.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Trang chủ')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MyApp(routerConfig: router),
      ),
    );
    await tester.pump();

    ThemeData themeAt() => Theme.of(tester.element(find.text('Trang chủ')));

    // Mặc định: Security Minimal + light (test binding chạy platform light).
    expect(
      themeAt().scaffoldBackgroundColor,
      AppStylePalette.of(AppStyle.securityMinimal, Brightness.light).background,
    );

    await cubit.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      themeAt().scaffoldBackgroundColor,
      AppStylePalette.of(AppStyle.securityMinimal, Brightness.dark).background,
    );

    await cubit.setStyle(AppStyle.oledDark);
    await tester.pumpAndSettle();
    expect(themeAt().scaffoldBackgroundColor, const Color(0xFF000000));
    expect(
      themeAt().extension<AppStyleTokens>()!.otpCodeColor,
      AppStylePalette.of(AppStyle.oledDark, Brightness.dark).otpCode,
    );

    await cubit.setStyle(AppStyle.darkCinema);
    await tester.pumpAndSettle();
    expect(
      themeAt().scaffoldBackgroundColor,
      AppStylePalette.of(AppStyle.darkCinema, Brightness.dark).background,
    );
  });

  testWidgets('theme áp dụng ngay khi storage còn đang chờ ghi', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = _BlockingStore();
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final preferences = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(preferences);
    addTearDown(cubit.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Trang chủ')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MyApp(routerConfig: router),
      ),
    );
    await tester.pump();

    ThemeData themeAt() => Theme.of(tester.element(find.text('Trang chủ')));

    final pendingMode = cubit.setThemeMode(ThemeMode.dark);
    final pendingStyle = cubit.setStyle(AppStyle.oledDark);
    await tester.pumpAndSettle();

    // Cả hai write vẫn treo nhưng UI đã đổi theme xong.
    expect(store.pendingWrites, hasLength(2));
    expect(themeAt().scaffoldBackgroundColor, const Color(0xFF000000));

    for (final write in store.pendingWrites) {
      write.complete(true);
    }
    await Future.wait([pendingMode, pendingStyle]);
    await tester.pumpAndSettle();

    expect(themeAt().scaffoldBackgroundColor, const Color(0xFF000000));
    final restored = ThemeCubit(preferences).state;
    expect(restored.mode, ThemeMode.dark);
    expect(restored.style, AppStyle.oledDark);
  });
}
