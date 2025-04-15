import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModePrefKey = 'theme_mode'; // Reuse key

class ThemeProvider with ChangeNotifier {
  final SharedPreferences sharedPreferences;
  ThemeMode _themeMode = ThemeMode.system; // Default

  ThemeProvider(this.sharedPreferences) {
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;

  void _loadThemeMode() {
    final String savedThemeMode =
        sharedPreferences.getString(_themeModePrefKey) ?? ThemeMode.system.name;
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == savedThemeMode,
      orElse: () => ThemeMode.system,
    );
    // No need to notify listeners here as it's called during initialization
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    if (_themeMode == themeMode) return; // No change

    _themeMode = themeMode;
    try {
      await sharedPreferences.setString(_themeModePrefKey, themeMode.name);
      notifyListeners(); // Notify listeners about the change
    } catch (e) {
      // Handle potential error saving preference
      debugPrint("Error saving theme mode preference: $e");
      // Optionally revert _themeMode or handle error differently
    }
  }
}
