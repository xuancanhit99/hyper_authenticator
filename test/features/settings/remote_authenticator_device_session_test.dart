import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/data/models/remote_authenticator_device_session.dart';

void main() {
  test('parse exact registry response và normalize timestamp về UTC', () {
    final session = RemoteAuthenticatorDeviceSession.fromRow({
      'registration_id': '10000000-0000-4000-8000-000000000001',
      'display_name': 'Hyper Authenticator trên Linux',
      'platform': 'linux',
      'registered_at': '2026-07-19T07:00:00+07:00',
      'last_seen_at': '2026-07-19T08:00:00+07:00',
      'is_current': true,
    });

    expect(session.registrationId, endsWith('0001'));
    expect(session.registeredAt, DateTime.utc(2026, 7, 19));
    expect(session.lastSeenAt, DateTime.utc(2026, 7, 19, 1));
    expect(session.isCurrent, isTrue);
  });

  test('từ chối row thiếu current marker hoặc timestamp hợp lệ', () {
    expect(
      () => RemoteAuthenticatorDeviceSession.fromRow({
        'registration_id': '10000000-0000-4000-8000-000000000001',
        'display_name': 'Hyper Authenticator trên Linux',
        'platform': 'linux',
        'registered_at': 'invalid',
        'last_seen_at': '2026-07-19T08:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('từ chối platform ngoài allowlist và timestamp quay ngược', () {
    expect(
      () => RemoteAuthenticatorDeviceSession.fromRow({
        'registration_id': '10000000-0000-4000-8000-000000000001',
        'display_name': 'Unknown client',
        'platform': 'other',
        'registered_at': '2026-07-19T08:00:00Z',
        'last_seen_at': '2026-07-19T07:00:00Z',
        'is_current': false,
      }),
      throwsFormatException,
    );
  });
}
