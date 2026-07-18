import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
// Added for ThemeMode
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_event.dart';
part 'settings_state.dart';

const String _biometricPrefKey = 'biometric_enabled';

@injectable
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SharedPreferences sharedPreferences;
  final LocalAuthentication localAuthentication;

  SettingsBloc({
    required this.sharedPreferences,
    required this.localAuthentication,
  }) : super(SettingsLoading()) {
    on<LoadSettings>(_onLoadSettings);
    on<ToggleBiometric>(_onToggleBiometric);
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    // Don't emit loading if already loaded to avoid flicker
    // if (state is! SettingsLoaded) {
    emit(SettingsLoading());
    // }
    try {
      final bool isEnabled =
          sharedPreferences.getBool(_biometricPrefKey) ?? false;
      final bool canCheck = await _checkBiometricSupport();

      emit(
        SettingsLoaded(
          isBiometricEnabled:
              isEnabled && canCheck, // Only enabled if supported
          canCheckBiometrics: canCheck,
        ),
      );
    } catch (e) {
      emit(SettingsError('Không thể tải cài đặt: ${e.toString()}'));
    }
  }

  Future<void> _onToggleBiometric(
    ToggleBiometric event,
    Emitter<SettingsState> emit,
  ) async {
    // Get current state to access canCheckBiometrics
    final currentState = state;
    bool canCheck = false;
    bool previousIsEnabled = false;
    // ThemeMode previousThemeMode = ThemeMode.system; // Removed

    if (currentState is SettingsLoaded) {
      canCheck = currentState.canCheckBiometrics;
      previousIsEnabled = currentState.isBiometricEnabled;
      // previousThemeMode = currentState.themeMode; // Removed
    } else {
      // If state is not loaded, re-check support (or handle error)
      canCheck = await _checkBiometricSupport();
      previousIsEnabled = sharedPreferences.getBool(_biometricPrefKey) ?? false;
    }

    if (!canCheck) {
      // Should ideally not happen if UI disables the switch, but double-check
      emit(const SettingsError('Thiết bị này không hỗ trợ sinh trắc học.'));
      // Reload settings to reflect correct state
      add(LoadSettings());
      return;
    }

    try {
      // Optimistically update UI first
      emit(
        SettingsLoaded(
          isBiometricEnabled: event.isEnabled,
          canCheckBiometrics: canCheck,
          // themeMode: previousThemeMode, // Removed
        ),
      );
      // Then save to preferences
      await sharedPreferences.setBool(_biometricPrefKey, event.isEnabled);
      // No need to emit again if save is successful
    } catch (e) {
      emit(
        SettingsError('Không thể lưu cài đặt sinh trắc học: ${e.toString()}'),
      );
      // Revert to previous state on error
      emit(
        SettingsLoaded(
          isBiometricEnabled: previousIsEnabled,
          canCheckBiometrics: canCheck,
          // themeMode: previousThemeMode, // Removed
        ),
      );
    }
  }

  Future<bool> _checkBiometricSupport() async {
    if (!PlatformCapabilities.supportsLocalAuthentication) {
      return false;
    }

    try {
      // isDeviceSupported() checks for PIN/Pattern/Passcode as well
      // canCheckBiometrics checks specifically for biometrics
      // Combine checks for broader compatibility
      final bool canCheckBio = await localAuthentication.canCheckBiometrics;
      final bool isDeviceSupported = await localAuthentication
          .isDeviceSupported();
      return canCheckBio || isDeviceSupported;
    } catch (e) {
      return false;
    }
  }
}
