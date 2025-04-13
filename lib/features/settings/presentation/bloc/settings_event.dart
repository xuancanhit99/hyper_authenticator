part of 'settings_bloc.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object> get props => [];
}

/// Event to load current settings (including biometric status and availability).
class LoadSettings extends SettingsEvent {}

/// Event to toggle the biometric setting.
class ToggleBiometric extends SettingsEvent {
  final bool isEnabled;

  const ToggleBiometric({required this.isEnabled});

  @override
  List<Object> get props => [isEnabled];
}
