part of 'settings_bloc.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object> get props => [];
}

/// Initial state or while loading settings.
class SettingsLoading extends SettingsState {}

/// State when settings are loaded successfully.
class SettingsLoaded extends SettingsState {
  final bool isBiometricEnabled; // Current toggle state
  final bool canCheckBiometrics; // If device supports biometrics

  const SettingsLoaded({
    required this.isBiometricEnabled,
    required this.canCheckBiometrics,
  });

  @override
  List<Object> get props => [isBiometricEnabled, canCheckBiometrics];
}

/// State when an error occurs loading or saving settings.
class SettingsError extends SettingsState {
  final String message;

  const SettingsError(this.message);

  @override
  List<Object> get props => [message];
}
