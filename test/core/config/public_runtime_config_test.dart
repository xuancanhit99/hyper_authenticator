import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/config/public_runtime_config.dart';

// Synthetic public key that only exercises the documented format.
const publishableKey =
    'sb_publishable_0123456789abcdefghij-__01234567'; // gitleaks:allow

String legacyKeyForRole(String role) {
  String encode(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'role': role, 'iss': 'supabase-test'})}.'
      'TEST_ONLY_SIGNATURE';
}

void main() {
  group('PublicRuntimeConfig', () {
    test('nhận HTTPS origin và publishable key đúng format', () {
      final config = PublicRuntimeConfig.validate(
        supabaseUrl: 'https://supabase.example.com',
        supabasePublishableKey: publishableKey,
        passwordRecoveryUrl: 'https://auth.example.com/reset-password/',
        allowInsecurePlaintextSync: false,
        releaseMode: true,
      );

      expect(config.cloudEnabled, isTrue);
      expect(config.supabaseUrl?.host, 'supabase.example.com');
      expect(config.passwordRecoveryUrl?.path, '/reset-password/');
    });

    test('cho phép local-only khi toàn bộ cloud config để trống', () {
      final config = PublicRuntimeConfig.validate(
        supabaseUrl: '',
        supabasePublishableKey: '',
        passwordRecoveryUrl: '',
        allowInsecurePlaintextSync: false,
        releaseMode: true,
      );

      expect(config.cloudEnabled, isFalse);
      expect(config.supabaseUrl, isNull);
      expect(config.supabasePublishableKey, isNull);
      expect(config.passwordRecoveryUrl, isNull);
    });

    test('từ chối cloud config thiếu URL hoặc publishable key', () {
      for (final values in [
        ('https://supabase.example.com', ''),
        ('', publishableKey),
      ]) {
        expect(
          () => PublicRuntimeConfig.validate(
            supabaseUrl: values.$1,
            supabasePublishableKey: values.$2,
            passwordRecoveryUrl: '',
            allowInsecurePlaintextSync: false,
            releaseMode: false,
          ),
          throwsStateError,
        );
      }
    });

    test('giữ tương thích legacy anon JWT', () {
      final config = PublicRuntimeConfig.validate(
        supabaseUrl: 'https://supabase.example.com/',
        supabasePublishableKey: legacyKeyForRole('anon'),
        passwordRecoveryUrl: 'https://auth.example.com/reset-password/',
        allowInsecurePlaintextSync: false,
        releaseMode: false,
      );

      expect(config.passwordRecoveryUrl?.host, 'auth.example.com');
    });

    test('từ chối HTTP và Supabase URL có path', () {
      expect(
        () => PublicRuntimeConfig.validate(
          supabaseUrl: 'http://supabase.example.com',
          supabasePublishableKey: publishableKey,
          passwordRecoveryUrl: '',
          allowInsecurePlaintextSync: false,
          releaseMode: false,
        ),
        throwsStateError,
      );
      expect(
        () => PublicRuntimeConfig.validate(
          supabaseUrl: 'https://supabase.example.com/rest/v1',
          supabasePublishableKey: publishableKey,
          passwordRecoveryUrl: '',
          allowInsecurePlaintextSync: false,
          releaseMode: false,
        ),
        throwsStateError,
      );
    });

    test('từ chối sb_secret và legacy service_role key', () {
      for (final unsafeKey in [
        ['sb', 'secret', 'test-only-rejected-key'].join('_'),
        legacyKeyForRole('service_role'),
      ]) {
        expect(
          () => PublicRuntimeConfig.validate(
            supabaseUrl: 'https://supabase.example.com',
            supabasePublishableKey: unsafeKey,
            passwordRecoveryUrl: '',
            allowInsecurePlaintextSync: false,
            releaseMode: false,
          ),
          throwsStateError,
        );
      }
    });

    test('không đưa key bị từ chối vào error message', () {
      const unsafeKey = 'SERVER_CREDENTIAL_MUST_NOT_BE_LOGGED';

      expect(
        () => PublicRuntimeConfig.validate(
          supabaseUrl: 'https://supabase.example.com',
          supabasePublishableKey: unsafeKey,
          passwordRecoveryUrl: '',
          allowInsecurePlaintextSync: false,
          releaseMode: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(unsafeKey)),
          ),
        ),
      );
    });

    test('cloud luôn bắt buộc recovery URL', () {
      for (final releaseMode in [false, true]) {
        expect(
          () => PublicRuntimeConfig.validate(
            supabaseUrl: 'https://supabase.example.com',
            supabasePublishableKey: publishableKey,
            passwordRecoveryUrl: '',
            allowInsecurePlaintextSync: false,
            releaseMode: releaseMode,
          ),
          throwsStateError,
        );
      }
    });

    test('recovery URL không được đứng riêng trong local-only mode', () {
      expect(
        () => PublicRuntimeConfig.validate(
          supabaseUrl: '',
          supabasePublishableKey: '',
          passwordRecoveryUrl: 'https://auth.example.com/reset-password/',
          allowInsecurePlaintextSync: false,
          releaseMode: false,
        ),
        throwsStateError,
      );
    });

    test('mọi build luôn từ chối plaintext sync flag đã retired', () {
      expect(
        () => PublicRuntimeConfig.validate(
          supabaseUrl: 'https://supabase.example.com',
          supabasePublishableKey: publishableKey,
          passwordRecoveryUrl: '',
          allowInsecurePlaintextSync: true,
          releaseMode: false,
        ),
        throwsStateError,
      );
    });

    test('recovery URL từ chối user info, query và fragment', () {
      for (final unsafeUrl in [
        'https://user@auth.example.com/reset-password/',
        'https://auth.example.com/reset-password/?token=unsafe',
        'https://auth.example.com/reset-password/#token',
      ]) {
        expect(
          () => PublicRuntimeConfig.validate(
            supabaseUrl: 'https://supabase.example.com',
            supabasePublishableKey: publishableKey,
            passwordRecoveryUrl: unsafeUrl,
            allowInsecurePlaintextSync: false,
            releaseMode: false,
          ),
          throwsStateError,
        );
      }
    });
  });
}
