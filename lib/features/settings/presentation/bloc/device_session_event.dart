part of 'device_session_bloc.dart';

sealed class DeviceSessionEvent extends Equatable {
  const DeviceSessionEvent();

  @override
  List<Object> get props => const [];
}

final class LoadDeviceSessionsRequested extends DeviceSessionEvent {
  final String userId;

  const LoadDeviceSessionsRequested(this.userId);

  @override
  List<Object> get props => [userId];

  @override
  String toString() => 'LoadDeviceSessionsRequested(<redacted>)';
}

final class RevokeDeviceSessionRequested extends DeviceSessionEvent {
  final String userId;
  final String registrationId;

  const RevokeDeviceSessionRequested({
    required this.userId,
    required this.registrationId,
  });

  @override
  List<Object> get props => [userId, registrationId];

  @override
  String toString() => 'RevokeDeviceSessionRequested(<redacted>)';
}
