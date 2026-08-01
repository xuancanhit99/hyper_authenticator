import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// In-memory store có thể fail N lượt ghi đầu tiên hoặc fail theo key để tái
/// hiện race giữa optimistic emit và persistence thất bại. `staleGetAll` mô
/// phỏng snapshot cũ: nếu repair dùng `reload()` toàn cache, nó sẽ áp snapshot
/// này đè lên write vừa thành công của key khác.
class _FlakyStore extends SharedPreferencesStorePlatform {
  _FlakyStore({this.failWrites = 0, Set<String>? failKeys})
    : failKeys = failKeys ?? {};

  int failWrites;
  final Set<String> failKeys;
  Map<String, Object>? staleGetAll;
  final Map<String, Object> _data = {};
  int setCalls = 0;

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => staleGetAll ?? Map.of(_data);

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setCalls++;
    if (failKeys.any(key.endsWith)) return false;
    if (failWrites > 0) {
      failWrites--;
      return false;
    }
    _data[key] = value;
    return true;
  }
}

class _PendingWrite {
  _PendingWrite({required this.key, required this.value});

  final String key;
  final Object value;
  final Completer<bool> result = Completer<bool>();
}

/// Store điều khiển từng completion để khóa race khi một write cũ đã in-flight
/// rồi người dùng chọn A → B → A.
class _ControlledStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> _data = {};
  final List<_PendingWrite> pendingWrites = [];

  Object? persisted(String key) => _data['flutter.$key'];

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
    final write = _PendingWrite(key: key, value: value);
    pendingWrites.add(write);
    return write.result.future.then((accepted) {
      if (accepted) _data[key] = value;
      return accepted;
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> preferencesWith([
    Map<String, Object> values = const {},
  ]) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('mặc định là system mode + style Security Minimal', () async {
    final cubit = ThemeCubit(await preferencesWith());

    expect(cubit.state.mode, ThemeMode.system);
    expect(cubit.state.style, AppStyle.securityMinimal);
  });

  test('mode và style đã lưu round-trip qua instance mới', () async {
    final preferences = await preferencesWith();
    final cubit = ThemeCubit(preferences);

    await cubit.setThemeMode(ThemeMode.dark);
    await cubit.setStyle(AppStyle.oledDark);

    final restored = ThemeCubit(preferences);
    expect(restored.state.mode, ThemeMode.dark);
    expect(restored.state.style, AppStyle.oledDark);
  });

  test('đổi style không làm mất mode đã chọn và ngược lại', () async {
    final cubit = ThemeCubit(await preferencesWith());

    await cubit.setThemeMode(ThemeMode.light);
    await cubit.setStyle(AppStyle.darkCinema);

    expect(cubit.state.mode, ThemeMode.light);
    expect(cubit.state.style, AppStyle.darkCinema);
  });

  test('giá trị lạ trong storage rơi về default thay vì crash', () async {
    final cubit = ThemeCubit(
      await preferencesWith({
        'theme_mode': 'neon',
        'app_style': 'does_not_exist',
      }),
    );

    expect(cubit.state.mode, ThemeMode.system);
    expect(cubit.state.style, AppStyle.securityMinimal);
  });

  test(
    'preference sai kiểu rơi về default thay vì throw lúc bootstrap',
    () async {
      final cubit = ThemeCubit(
        await preferencesWith({'theme_mode': 42, 'app_style': true}),
      );

      expect(cubit.state.mode, ThemeMode.system);
      expect(cubit.state.style, AppStyle.securityMinimal);
    },
  );

  test(
    'request trung gian bị skip; request cuối fail thì rollback về confirmed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _FlakyStore(failWrites: 2);
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final cubit = ThemeCubit(await SharedPreferences.getInstance());

      // OLED bị supersede trước khi vào platform. Cinema write và lượt ghi bù
      // đều bị từ chối.
      final first = cubit.setStyle(AppStyle.oledDark);
      final second = cubit.setStyle(AppStyle.darkCinema);
      await Future.wait([first, second]);

      // OLED chưa từng persist thành công nên không được trở thành state cuối.
      expect(cubit.state.style, AppStyle.securityMinimal);
      expect(store.setCalls, 2);
    },
  );

  test(
    'ABA style giữ request cuối khi write A cũ đang chạy rồi fail',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _ControlledStore();
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final preferences = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(preferences);

      final first = cubit.setStyle(AppStyle.oledDark);
      await pumpEventQueue();
      expect(store.pendingWrites, hasLength(1));

      final middle = cubit.setStyle(AppStyle.darkCinema);
      final latest = cubit.setStyle(AppStyle.oledDark);

      // Write OLED cũ fail; ghi bù về confirmed Security Minimal hoàn tất.
      store.pendingWrites[0].result.complete(false);
      await pumpEventQueue();
      expect(store.pendingWrites, hasLength(2));
      expect(store.pendingWrites[1].value, AppStyle.securityMinimal.name);
      store.pendingWrites[1].result.complete(true);
      await pumpEventQueue();

      // Request Cinema bị skip, còn request OLED mới nhất vẫn phải được ghi.
      expect(store.pendingWrites, hasLength(3));
      expect(store.pendingWrites[2].value, AppStyle.oledDark.name);
      store.pendingWrites[2].result.complete(true);
      await Future.wait([first, middle, latest]);

      expect(cubit.state.style, AppStyle.oledDark);
      expect(ThemeCubit(preferences).state.style, AppStyle.oledDark);
      expect(store.persisted('app_style'), AppStyle.oledDark.name);
    },
  );

  test('ABA mode giữ request cuối khi write A cũ đang chạy rồi fail', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _ControlledStore();
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final preferences = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(preferences);

    final first = cubit.setThemeMode(ThemeMode.dark);
    await pumpEventQueue();
    expect(store.pendingWrites, hasLength(1));

    final middle = cubit.setThemeMode(ThemeMode.light);
    final latest = cubit.setThemeMode(ThemeMode.dark);

    store.pendingWrites[0].result.complete(false);
    await pumpEventQueue();
    expect(store.pendingWrites, hasLength(2));
    expect(store.pendingWrites[1].value, ThemeMode.system.name);
    store.pendingWrites[1].result.complete(true);
    await pumpEventQueue();

    expect(store.pendingWrites, hasLength(3));
    expect(store.pendingWrites[2].value, ThemeMode.dark.name);
    store.pendingWrites[2].result.complete(true);
    await Future.wait([first, middle, latest]);

    expect(cubit.state.mode, ThemeMode.dark);
    expect(ThemeCubit(preferences).state.mode, ThemeMode.dark);
    expect(store.persisted('theme_mode'), ThemeMode.dark.name);
  });

  test(
    'ghi fail rollback về lựa chọn đã persist thành công trước đó',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _FlakyStore();
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final preferences = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(preferences);

      await cubit.setStyle(AppStyle.oledDark);
      expect(cubit.state.style, AppStyle.oledDark);

      store.failWrites = 1;
      await cubit.setStyle(AppStyle.darkCinema);

      expect(cubit.state.style, AppStyle.oledDark);
      // Cache đã được repair: instance mới trong cùng process không được đọc
      // giá trị bị từ chối (legacy SharedPreferences ghi cache trước khi
      // platform trả lời).
      expect(ThemeCubit(preferences).state.style, AppStyle.oledDark);
    },
  );

  test(
    'ghi fail khi không có request mới hơn thì rollback về giá trị cũ',
    () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FlakyStore(failWrites: 1);
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final preferences = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(preferences);

      await cubit.setStyle(AppStyle.oledDark);

      expect(cubit.state.style, AppStyle.securityMinimal);
      expect(ThemeCubit(preferences).state.style, AppStyle.securityMinimal);
    },
  );

  test('repair sau ghi fail không stomp cache của preference khác', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _FlakyStore(failKeys: {'theme_mode'});
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final preferences = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(preferences);

    // Hai write khác key thành công trước khi theme write fail.
    await cubit.setStyle(AppStyle.oledDark);
    await preferences.setString('sync_meta', 'TEST_ONLY_marker');
    // Snapshot cũ: nếu repair reload() toàn cache thì hai giá trị trên bị xóa.
    store.staleGetAll = <String, Object>{};

    await cubit.setThemeMode(ThemeMode.dark);

    expect(cubit.state.mode, ThemeMode.system);
    expect(preferences.getString('sync_meta'), 'TEST_ONLY_marker');
    final reReader = ThemeCubit(preferences);
    expect(reReader.state.style, AppStyle.oledDark);
    expect(reReader.state.mode, ThemeMode.system);
  });

  test('setString throw được xử lý như ghi fail, không crash', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _ThrowingStore();
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    final preferences = await SharedPreferences.getInstance();
    final cubit = ThemeCubit(preferences);

    await cubit.setThemeMode(ThemeMode.dark);

    expect(cubit.state.mode, ThemeMode.system);
    expect(ThemeCubit(preferences).state.mode, ThemeMode.system);
  });
}

class _ThrowingStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() async => true;

  @override
  Future<Map<String, Object>> getAll() async => {};

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    throw StateError('TEST_ONLY storage failure');
  }
}
