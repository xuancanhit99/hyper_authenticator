import 'package:equatable/equatable.dart';

class AuthenticatorDeviceSession extends Equatable {
  final String registrationId;
  final String displayName;
  final String platform;
  final DateTime registeredAt;
  final DateTime lastSeenAt;
  final bool isCurrent;

  const AuthenticatorDeviceSession({
    required this.registrationId,
    required this.displayName,
    required this.platform,
    required this.registeredAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  @override
  List<Object> get props => [
    registrationId,
    displayName,
    platform,
    registeredAt,
    lastSeenAt,
    isCurrent,
  ];

  @override
  String toString() =>
      'AuthenticatorDeviceSession(<redacted>, isCurrent: $isCurrent)';
}
