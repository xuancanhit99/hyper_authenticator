import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/chrome_extension/data/secure_supabase_storage.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';

void main() {
  late _MemorySecureStore store;

  setUp(() => store = _MemorySecureStore());

  test('Supabase session round-trip đi qua secure-store namespace', () async {
    final session = SecureSupabaseLocalStorage(store);

    expect(await session.hasAccessToken(), isFalse);
    await session.persistSession('TEST_ONLY_SESSION_VALUE');

    expect(await session.hasAccessToken(), isTrue);
    expect(await session.accessToken(), 'TEST_ONLY_SESSION_VALUE');
    expect(
      store.values.keys,
      contains('ha:chrome-extension:v1:supabase-session'),
    );

    await session.removePersistedSession();
    expect(await session.accessToken(), isNull);
  });

  test('PKCE verifier không dùng session key hoặc localStorage key', () async {
    final pkce = SecureSupabasePkceStorage(store);

    await pkce.setItem(key: 'code-verifier', value: 'TEST_ONLY_VERIFIER');

    expect(await pkce.getItem(key: 'code-verifier'), 'TEST_ONLY_VERIFIER');
    expect(
      store.values.keys,
      contains('ha:chrome-extension:v1:gotrue:code-verifier'),
    );
    await pkce.removeItem(key: 'code-verifier');
    expect(await pkce.getItem(key: 'code-verifier'), isNull);
  });
}

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
