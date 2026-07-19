import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_installation_identity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('tạo một installation UUID và round-trip ổn định', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AuthenticatorInstallationIdentityStore(
      preferences,
      const Uuid(),
    );

    final first = await store.readOrCreate();
    final second = await store.readOrCreate();

    expect(Uuid.isValidUUID(fromString: first.installationId), isTrue);
    expect(second.installationId, first.installationId);
    expect(
      preferences.getString(
        AuthenticatorInstallationIdentityStore.preferenceKey,
      ),
      first.installationId,
    );
    expect([
      'android',
      'ios',
      'macos',
      'windows',
      'linux',
      'web',
      'unknown',
    ], contains(first.platform));
    expect(first.displayName, startsWith('Hyper Authenticator trên '));
  });

  test(
    'metadata hỏng được thay bằng UUID mới không dùng làm credential',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthenticatorInstallationIdentityStore.preferenceKey: 'not-a-uuid',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = AuthenticatorInstallationIdentityStore(
        preferences,
        const Uuid(),
      );

      final identity = await store.readOrCreate();

      expect(identity.installationId, isNot('not-a-uuid'));
      expect(Uuid.isValidUUID(fromString: identity.installationId), isTrue);
    },
  );

  test('nil UUID hợp lệ về format vẫn bị thay vì không phải UUID v4', () async {
    SharedPreferences.setMockInitialValues({
      AuthenticatorInstallationIdentityStore.preferenceKey:
          '00000000-0000-0000-0000-000000000000',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = AuthenticatorInstallationIdentityStore(
      preferences,
      const Uuid(),
    );

    final identity = await store.readOrCreate();

    expect(
      identity.installationId,
      isNot('00000000-0000-0000-0000-000000000000'),
    );
    expect(identity.installationId.split('-')[2], startsWith('4'));
  });
}
