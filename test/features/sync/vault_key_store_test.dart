import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/vault_key_store.dart';
import 'package:hyper_authenticator/features/sync/domain/services/vault_cipher.dart';

void main() {
  test('initialize lưu DEK verified và recovery mở lại đúng key', () async {
    final storage = _MemorySecureStorage();
    final cipher = VaultCipher();
    final keyStore = VaultKeyStore(storage, cipher);

    final bundle = await keyStore.initializeForUser('TEST_ONLY_USER');
    expect(await keyStore.readDataKey('TEST_ONLY_USER'), bundle.dataKeyBytes);

    final recoveredStorage = _MemorySecureStorage();
    final recoveredStore = VaultKeyStore(recoveredStorage, cipher);
    final recovered = await recoveredStore.recoverForUser(
      userId: 'TEST_ONLY_USER',
      recoveryCode: bundle.recoveryCode,
      wrappedKey: bundle.wrappedDataKey,
    );
    expect(recovered, bundle.dataKeyBytes);
    expect(await recoveredStore.readDataKey('TEST_ONLY_USER'), recovered);
  });

  test('không silently thay DEK đã tồn tại', () async {
    final keyStore = VaultKeyStore(_MemorySecureStorage(), VaultCipher());
    await keyStore.initializeForUser('TEST_ONLY_USER');

    await expectLater(
      keyStore.initializeForUser('TEST_ONLY_USER'),
      throwsA(isA<VaultKeyStoreException>()),
    );
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
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
}
