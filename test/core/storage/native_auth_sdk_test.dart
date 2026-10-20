import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/storage/native_auth_storage.dart';
import 'package:hyper_authenticator/core/storage/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pinned SDK cold restore, refresh, logout and reopen use secure storage',
    () async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null; // Only the loopback fixture below is used.
      addTearDown(() => HttpOverrides.global = previousHttp);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String jwtPart(Object value) =>
          base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${jwtPart({'alg': 'HS256', 'typ': 'JWT'})}.${jwtPart({'sub': 'TEST_ONLY_USER', 'exp': 4102444800, 'aud': 'authenticated'})}.TEST_ONLY_SIGNATURE';
      Map<String, Object?> session(String refresh) => {
        'access_token': token.replaceFirst(
          'TEST_ONLY_SIGNATURE',
          'TEST_ONLY_$refresh',
        ),
        'refresh_token': refresh,
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'TEST_ONLY_USER',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      };
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path.endsWith('/logout')) {
          request.response.statusCode = 204;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(session('TEST_ONLY_REFRESHED')));
        }
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}';
      SharedPreferences.setMockInitialValues({
        'sb-127-auth-token': jsonEncode(session('TEST_ONLY_LEGACY')),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = _Store();
      final values = NativeAuthValues(store, prefs, url);
      Future<void> start() async {
        await Supabase.initialize(
          url: url,
          publishableKey: 'TEST_ONLY_PUBLIC_KEY',
          authOptions: FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: NativeSupabaseLocalStorage(values),
            pkceAsyncStorage: NativeSupabasePkceStorage(values),
          ),
        );
        // This SDK starts recoverSession lazily after initialize returns.
        // Drain its short local-only restore before issuing a manual refresh.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      Future<void> stored(
        String stage,
        bool Function(String?) predicate,
      ) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          if (predicate(await values.read(values.legacySessionKey))) return;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        fail('secure session persistence did not settle after $stage');
      }

      await start();
      expect(
        Supabase.instance.client.auth.currentSession?.refreshToken,
        'TEST_ONLY_LEGACY',
      );
      expect(prefs.getKeys(), isEmpty);
      await Supabase.instance.client.auth.refreshSession();
      await stored(
        'refresh',
        (value) => value?.contains('TEST_ONLY_REFRESHED') == true,
      );
      await Supabase.instance.dispose();
      await start();
      expect(
        Supabase.instance.client.auth.currentSession?.refreshToken,
        'TEST_ONLY_REFRESHED',
      );
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      await stored('logout', (value) => value == null);
      await Supabase.instance.dispose();
      await start();
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(prefs.getKeys(), isEmpty);
      await Supabase.instance.dispose();
    },
  );
}

class _Store implements SecureKeyValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read({required String key}) async => data[key];
  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
  @override
  Future<void> write({required String key, required String value}) async {
    data[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    data.remove(key);
  }
}
