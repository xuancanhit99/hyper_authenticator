import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'google_oauth_callback.dart';

/// Desktop callback listens only on IPv4 loopback, at a fresh port and an
/// unpredictable path. The PKCE verifier stays in the client's secure storage.
Future<void> completeLoopbackGoogleSignIn({
  required Future<Uri> Function(Uri redirect) authorizationUrl,
  required Future<bool> Function(Uri url) launchBrowser,
  required Future<void> Function(String code) exchangeCode,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final token = base64Url
      .encode(List.generate(24, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  final redirect = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: server.port,
    path: '/auth/callback/$token',
  );
  final callback = Completer<String>();
  final subscription = server.listen((request) async {
    request.response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; frame-ancestors 'none'",
      )
      ..contentType = ContentType.html;
    if (request.method != 'GET' ||
        request.uri.path != redirect.path ||
        request.headers.value(HttpHeaders.hostHeader) != redirect.authority) {
      request.response.statusCode = HttpStatus.notFound;
    } else if (callback.isCompleted) {
      request.response.statusCode = HttpStatus.gone;
    } else {
      try {
        final code = googleOAuthCallbackCode(
          redirect.resolveUri(request.uri),
          redirect,
        );
        callback.complete(code);
        request.response.write(
          '<!doctype html><html lang="vi"><meta charset="utf-8"><title>Hyper Authenticator</title><p>Bạn có thể quay lại Hyper Authenticator để hoàn tất đăng nhập.</p></html>',
        );
      } on FormatException {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(
          'Không thể hoàn tất đăng nhập. Quay lại ứng dụng để thử lại.',
        );
        if (request.uri.queryParameters.containsKey('error')) {
          callback.complete('');
        }
      }
    }
    await request.response.close();
  });
  try {
    final url = await authorizationUrl(redirect);
    if (!await launchBrowser(url)) throw StateError('Browser unavailable.');
    final code = await callback.future.timeout(timeout);
    if (code.isEmpty) throw StateError('OAuth cancelled.');
    await exchangeCode(code);
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}
