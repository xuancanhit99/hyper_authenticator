import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/storage/native_auth_storage.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionKey = 'sb-test-auth-token';
  const token =
      '{"refresh_token":"TEST_ONLY_REFRESH","access_token":"TEST_ONLY_ACCESS"}';
  late SharedPreferences prefs;
  late _Store store;
  late NativeAuthValues values;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      sessionKey: token,
      NativeAuthValues.pkceKey: 'TEST_ONLY_PKCE',
    });
    prefs = await SharedPreferences.getInstance();
    store = _Store();
    values = NativeAuthValues(store, prefs, 'https://test.example.invalid');
  });

  test(
    'cold start migrates session and PKCE; refresh and logout stay secure',
    () async {
      final local = NativeSupabaseLocalStorage(values);
      await local.initialize();
      expect(await local.accessToken(), token);
      expect(prefs.getKeys(), isEmpty);
      final pkce = NativeSupabasePkceStorage(values);
      expect(
        await pkce.getItem(key: NativeAuthValues.pkceKey),
        'TEST_ONLY_PKCE',
      );
      await local.persistSession('TEST_ONLY_REFRESHED');
      values = NativeAuthValues(store, prefs, 'https://test.example.invalid');
      expect(
        await NativeSupabaseLocalStorage(values).accessToken(),
        'TEST_ONLY_REFRESHED',
      );
      await local.removePersistedSession();
      await pkce.removeItem(key: NativeAuthValues.pkceKey);
      expect(await local.hasAccessToken(), isFalse);
      expect(await pkce.getItem(key: NativeAuthValues.pkceKey), isNull);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  for (final failure in ['throw', 'drop']) {
    test(
      'migration $failure preserves legacy and never falls back to it',
      () async {
        store.failure = failure;
        await expectLater(values.initialize(), throwsA(anything));
        expect(prefs.getString(sessionKey), token);
        store.failure = null;
        await NativeSupabaseLocalStorage(values).initialize();
        expect(prefs.getKeys(), isEmpty);
        expect(await NativeSupabaseLocalStorage(values).accessToken(), token);
      },
    );
  }

  test(
    'interrupted cleanup keeps verified newer session authoritative',
    () async {
      store.data['${values.namespace}$sessionKey'] = jsonEncode({
        'version': 1,
        'value': 'TEST_ONLY_NEWER',
      });
      expect(await values.read(sessionKey), 'TEST_ONLY_NEWER');
      expect(prefs.containsKey(sessionKey), isFalse);
    },
  );

  test(
    'logout tombstone prevents legacy session resurrection after interruption',
    () async {
      await values.write(sessionKey, null);
      await prefs.setString(
        sessionKey,
        token,
      ); // Simulate stale legacy left by interrupted cleanup.
      final reopened = NativeAuthValues(
        store,
        prefs,
        'https://test.example.invalid',
      );
      expect(await reopened.read(sessionKey), isNull);
      expect(prefs.containsKey(sessionKey), isFalse);
    },
  );

  test('corrupt secure envelope does not select legacy plaintext', () async {
    store.data['${values.namespace}$sessionKey'] = 'TEST_ONLY_CORRUPT';
    await expectLater(values.read(sessionKey), throwsFormatException);
    expect(prefs.getString(sessionKey), token);
  });
}

class _Store implements SecureKeyValueStore {
  final data = <String, String>{};
  String? failure;
  @override
  Future<String?> read({required String key}) async => data[key];
  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
  @override
  Future<void> write({required String key, required String value}) async {
    if (failure == 'throw') throw StateError('TEST_ONLY unavailable');
    if (failure != 'drop') data[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => data.remove(key);
}
