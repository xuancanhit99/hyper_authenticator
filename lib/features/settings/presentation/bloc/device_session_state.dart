part of 'device_session_bloc.dart';

sealed class DeviceSessionState extends Equatable {
  const DeviceSessionState();

  String? get userId => null;
  List<AuthenticatorDeviceSession> get devices => const [];

  @override
  List<Object> get props => const [];

  @override
  String toString() => '$runtimeType(<redacted>)';
}

final class DeviceSessionInitial extends DeviceSessionState {
  const DeviceSessionInitial();
}

final class DeviceSessionLoading extends DeviceSessionState {
  @override
  final String userId;

  const DeviceSessionLoading(this.userId);

  @override
  List<Object> get props => [userId];

  @override
  String toString() => 'DeviceSessionLoading(<redacted>)';
}

final class DeviceSessionsLoaded extends DeviceSessionState {
  @override
  final String userId;
  @override
  final List<AuthenticatorDeviceSession> devices;

  const DeviceSessionsLoaded(this.userId, this.devices);

  @override
  List<Object> get props => [userId, devices];
}

final class DeviceSessionRevoking extends DeviceSessionState {
  @override
  final String userId;
  @override
  final List<AuthenticatorDeviceSession> devices;
  final String registrationId;

  const DeviceSessionRevoking(this.userId, this.devices, this.registrationId);

  @override
  List<Object> get props => [userId, devices, registrationId];

  @override
  String toString() => 'DeviceSessionRevoking(<redacted>)';
}

final class DeviceSessionRevocationSuccess extends DeviceSessionState {
  @override
  final String userId;
  @override
  final List<AuthenticatorDeviceSession> devices;
  final String displayName;

  const DeviceSessionRevocationSuccess(
    this.userId,
    this.devices,
    this.displayName,
  );

  @override
  List<Object> get props => [userId, devices, displayName];
}

final class DeviceSessionLoadFailure extends DeviceSessionState {
  @override
  final String userId;
  final String message;

  const DeviceSessionLoadFailure(this.userId, this.message);

  @override
  List<Object> get props => [userId, message];
}

final class DeviceSessionActionFailure extends DeviceSessionState {
  @override
  final String userId;
  @override
  final List<AuthenticatorDeviceSession> devices;
  final String message;

  const DeviceSessionActionFailure(this.userId, this.devices, this.message);

  @override
  List<Object> get props => [userId, devices, message];
}
