import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/auth/data/oauth/google_oauth_callback.dart';
import 'package:hyper_authenticator/features/auth/data/oauth/google_oauth_loopback.dart';

void main() {
  final expected = Uri.parse(
    'https://test-extension.chromiumapp.org/auth/callback',
  );
  test('callback accepts only one bounded code for exact redirect', () {
    expect(
      googleOAuthCallbackCode(
        expected.replace(query: 'code=TEST_ONLY'),
        expected,
      ),
      'TEST_ONLY',
    );
    for (final bad in [
      'https://evil.invalid/auth/callback?code=TEST_ONLY',
      'https://test-extension.chromiumapp.org/other?code=TEST_ONLY',
      'https://user@test-extension.chromiumapp.org/auth/callback?code=TEST_ONLY',
      'https://test-extension.chromiumapp.org/auth/callback?code=a&code=b',
      'https://test-extension.chromiumapp.org/auth/callback?error=access_denied',
      'https://test-extension.chromiumapp.org/auth/callback#access_token=TEST_ONLY',
      'https://test-extension.chromiumapp.org/auth/callback?code=',
    ]) {
      expect(
        () => googleOAuthCallbackCode(Uri.parse(bad), expected),
        throwsFormatException,
      );
    }
  });

  test(
    'desktop loopback rejects unrelated requests, exchanges once and closes',
    () async {
      final http = HttpClient();
      addTearDown(http.close);
      Uri? redirect;
      final exchanges = <String>[];
      Future<int> request(Uri uri) async {
        final response = await (await http.getUrl(uri)).close();
        expect(response.headers.value('cache-control'), 'no-store');
        await response.drain<void>();
        return response.statusCode;
      }

      await completeLoopbackGoogleSignIn(
        authorizationUrl: (uri) async {
          redirect = uri;
          return Uri.parse('https://example.invalid/authorize');
        },
        launchBrowser: (_) async {
          expect(redirect!.host, '127.0.0.1');
          expect(
            redirect!.path.split('/').last.length,
            greaterThanOrEqualTo(32),
          );
          expect(await request(redirect!.replace(path: '/wrong')), 404);
          expect(await request(redirect!.replace(query: 'code=a&code=b')), 400);
          expect(
            await request(redirect!.replace(query: 'code=TEST_ONLY')),
            200,
          );
          return true;
        },
        exchangeCode: (code) async {
          exchanges.add(code);
        },
      );
      expect(exchanges, ['TEST_ONLY']);
      await expectLater(
        Socket.connect(redirect!.host, redirect!.port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'desktop timeout/browser failure release listener without exchange',
    () async {
      for (final launched in [false, true]) {
        var exchanged = false;
        await expectLater(
          completeLoopbackGoogleSignIn(
            authorizationUrl: (_) async => Uri.parse('https://example.invalid'),
            launchBrowser: (_) async => launched,
            exchangeCode: (_) async {
              exchanged = true;
            },
            timeout: const Duration(milliseconds: 20),
          ),
          throwsA(launched ? isA<TimeoutException>() : isA<StateError>()),
        );
        expect(exchanged, false);
      }
    },
  );
}
