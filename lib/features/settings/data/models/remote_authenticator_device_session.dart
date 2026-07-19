import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:uuid/uuid.dart';

class RemoteAuthenticatorDeviceSession extends AuthenticatorDeviceSession {
  const RemoteAuthenticatorDeviceSession({
    required super.registrationId,
    required super.displayName,
    required super.platform,
    required super.registeredAt,
    required super.lastSeenAt,
    required super.isCurrent,
  });

  factory RemoteAuthenticatorDeviceSession.fromRow(Map<String, dynamic> row) {
    final registrationId = row['registration_id'];
    final displayName = row['display_name'];
    final platform = row['platform'];
    final registeredAt = DateTime.tryParse(
      row['registered_at']?.toString() ?? '',
    );
    final lastSeenAt = DateTime.tryParse(row['last_seen_at']?.toString() ?? '');
    final isCurrent = row['is_current'];
    if (registrationId is! String ||
        !Uuid.isValidUUID(fromString: registrationId) ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        platform is! String ||
        platform.isEmpty ||
        registeredAt == null ||
        lastSeenAt == null ||
        isCurrent is! bool ||
        !const {
          'android',
          'ios',
          'macos',
          'windows',
          'linux',
          'web',
          'unknown',
        }.contains(platform) ||
        lastSeenAt.isBefore(registeredAt)) {
      throw const FormatException('Device session response không hợp lệ.');
    }
    return RemoteAuthenticatorDeviceSession(
      registrationId: registrationId,
      displayName: displayName,
      platform: platform,
      registeredAt: registeredAt.toUtc(),
      lastSeenAt: lastSeenAt.toUtc(),
      isCurrent: isCurrent,
    );
  }
}
