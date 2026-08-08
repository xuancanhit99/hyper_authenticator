import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModePrefKey = 'theme_mode';
const String _appStylePrefKey = 'app_style';

class ThemeState extends Equatable {
  const ThemeState({required this.mode, required this.style});

  final ThemeMode mode;
  final AppStyle style;

  ThemeState copyWith({ThemeMode? mode, AppStyle? style}) {
    return ThemeState(mode: mode ?? this.mode, style: style ?? this.style);
  }

  @override
  List<Object> get props => [mode, style];
}

/// Owner của lựa chọn giao diện. Persistence contract:
///
/// - Ghi được serialize theo từng key; request có revision cũ hơn được bỏ qua
///   trước khi bắt đầu. Request đã in-flight vẫn hoàn tất tuần tự nhưng không
///   được rollback UI. Revision thay vì so sánh value tránh nhầm chuỗi A → B →
///   A là cùng một request.
/// - Cubit giữ "confirmed value" — giá trị đọc lên lúc khởi tạo hoặc đã ghi
///   thành công. Ghi thất bại rollback về confirmed value, không phải về một
///   lựa chọn trung gian chưa từng persist.
/// - Legacy `SharedPreferences` cập nhật Dart cache trước khi platform xác
///   nhận, nên sau một lượt ghi bị từ chối cache được sửa bằng MỘT LƯỢT GHI BÙ
///   trên đúng key đó về giá trị đã xác nhận. Không dùng `reload()`: cache dùng
///   chung toàn app, reload có thể áp snapshot cũ đè lên write vừa thành công
///   của preference khác (biometric/sync metadata). Durable platform state vẫn
///   là best-effort khi chính plugin báo lỗi; API legacy không cam kết một
///   setter thất bại chưa từng mutate platform storage.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit(this._preferences) : super(_readInitial(_preferences)) {
    _confirmedMode = state.mode;
    _confirmedStyle = state.style;
  }

  final SharedPreferences _preferences;

  late ThemeMode _confirmedMode;
  late AppStyle _confirmedStyle;
  Future<void> _modeWrites = Future<void>.value();
  Future<void> _styleWrites = Future<void>.value();
  int _latestModeRequest = 0;
  int _latestStyleRequest = 0;

  static ThemeState _readInitial(SharedPreferences preferences) {
    final mode = ThemeMode.values.firstWhere(
      (candidate) =>
          candidate.name == _readString(preferences, _themeModePrefKey),
      orElse: () => ThemeMode.system,
    );
    final style = AppStyle.fromName(_readString(preferences, _appStylePrefKey));
    return ThemeState(mode: mode, style: style);
  }

  /// Preference đọc lên phải fallback về default, kể cả khi value tồn tại
  /// nhưng sai kiểu (getString throw TypeError) — không được chặn bootstrap.
  static String? _readString(SharedPreferences preferences, String key) {
    try {
      return preferences.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) {
    if (state.mode == mode) return Future<void>.value();
    final request = ++_latestModeRequest;
    emit(state.copyWith(mode: mode));
    return _modeWrites = _modeWrites.then((_) => _persistMode(mode, request));
  }

  Future<void> setStyle(AppStyle style) {
    if (state.style == style) return Future<void>.value();
    final request = ++_latestStyleRequest;
    emit(state.copyWith(style: style));
    return _styleWrites = _styleWrites.then(
      (_) => _persistStyle(style, request),
    );
  }

  Future<void> _persistMode(ThemeMode mode, int request) async {
    if (request != _latestModeRequest) return;
    if (await _write(_themeModePrefKey, mode.name)) {
      _confirmedMode = mode;
      return;
    }
    await _repairKey(_themeModePrefKey, _confirmedMode.name);
    if (!isClosed && request == _latestModeRequest) {
      emit(state.copyWith(mode: _confirmedMode));
    }
  }

  Future<void> _persistStyle(AppStyle style, int request) async {
    if (request != _latestStyleRequest) return;
    if (await _write(_appStylePrefKey, style.name)) {
      _confirmedStyle = style;
      return;
    }
    await _repairKey(_appStylePrefKey, _confirmedStyle.name);
    if (!isClosed && request == _latestStyleRequest) {
      emit(state.copyWith(style: _confirmedStyle));
    }
  }

  Future<bool> _write(String key, String value) async {
    try {
      return await _preferences.setString(key, value);
    } catch (_) {
      return false;
    }
  }

  /// Ghi bù giá trị đã xác nhận vào đúng key vừa fail. Dart cache được set đồng
  /// bộ ngay cả khi platform lại từ chối, không chạm cache của preference khác.
  /// Plugin legacy không cung cấp transaction/read-back theo key nên durable
  /// platform state vẫn là best-effort trong chính failure path này.
  Future<void> _repairKey(String key, String confirmedValue) async {
    try {
      await _preferences.setString(key, confirmedValue);
    } catch (_) {
      // Cache đã được set đồng bộ trước khi platform kịp throw.
    }
  }
}
