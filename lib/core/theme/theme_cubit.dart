import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModePrefKey = 'theme_mode';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._preferences) : super(_readInitial(_preferences));

  final SharedPreferences _preferences;

  static ThemeMode _readInitial(SharedPreferences preferences) {
    final saved = preferences.getString(_themeModePrefKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;

    final previous = state;
    emit(mode);
    final saved = await _preferences.setString(_themeModePrefKey, mode.name);
    if (!saved) emit(previous);
  }
}
