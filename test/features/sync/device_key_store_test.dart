import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_store.dart';
import 'package:hyper_authenticator/features/sync/domain/services/device_key_cipher.dart';

void main() {
  group('DeviceKeyStore', () {
    late _MemorySecureStorage storage;
    late DeviceKeyStore keyStore;

    setUp(() {
      storage = _MemorySecureStorage();
      keyStore = DeviceKeyStore(storage, DeviceKeyCipher());
    });

    test('getOrCreate persist và trả lại đúng key material', () async {
      final created = await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );
      final reopened = await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );

      expect(reopened.privateKeyBytes, created.privateKeyBytes);
      expect(reopened.publicKeyBytes, created.publicKeyBytes);
      expect(reopened.bindingSecretBytes, created.bindingSecretBytes);
      expect(storage.values, hasLength(1));
      expect(storage.values.values.single, isNot(contains('TEST_ONLY_USER_A')));
    });

    test('tách key theo user và installation', () async {
      final first = await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );
      final second = await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER_B',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );

      expect(second.privateKeyBytes, isNot(first.privateKeyBytes));
      expect(second.bindingSecretBytes, isNot(first.bindingSecretBytes));
      expect(storage.values, hasLength(2));
    });

    test('storage key không collision khi identifier chứa delimiter', () async {
      final first = await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER:A',
        installationId: 'B',
      );
      final second = await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER',
        installationId: 'A:B',
      );

      expect(second.privateKeyBytes, isNot(first.privateKeyBytes));
      expect(storage.values, hasLength(2));
      expect(
        storage.values.keys.every((key) => !key.contains('TEST_ONLY_USER')),
        isTrue,
      );
    });

    test('hai initialization đồng thời dùng cùng một key material', () async {
      final results = await Future.wait([
        keyStore.getOrCreate(
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
        ),
        keyStore.getOrCreate(
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
        ),
      ]);

      expect(results[1].privateKeyBytes, results[0].privateKeyBytes);
      expect(results[1].bindingSecretBytes, results[0].bindingSecretBytes);
      expect(storage.values, hasLength(1));
    });

    test('record corrupt fail closed và không tự thay key', () async {
      await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );
      storage.values.updateAll((_, _) => 'not-base64');

      await expectLater(
        keyStore.getOrCreate(
          userId: 'TEST_ONLY_USER_A',
          installationId: 'TEST_ONLY_INSTALLATION_A',
        ),
        throwsA(isA<DeviceKeyStoreException>()),
      );
      expect(storage.values.values.single, 'not-base64');
    });

    test('delete device key verify secure storage đã xóa', () async {
      await keyStore.getOrCreate(
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );

      await keyStore.delete(
        userId: 'TEST_ONLY_USER_A',
        installationId: 'TEST_ONLY_INSTALLATION_A',
      );

      expect(storage.values, isEmpty);
    });
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
