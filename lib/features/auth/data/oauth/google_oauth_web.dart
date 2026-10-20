import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:hyper_authenticator/core/config/chrome_extension_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_oauth_callback.dart';

@JS('location.origin')
external String get _origin;

Future<void> startGoogleSignIn(SupabaseClient client) async {
  if (!ChromeExtensionRuntime.isEnabled) {
    final origin = Uri.parse(_origin);
    if (origin.scheme != 'https' &&
        !(origin.scheme == 'http' &&
            const ['localhost', '127.0.0.1'].contains(origin.host))) {
      throw StateError('Secure OAuth origin required.');
    }
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: origin.resolve('/login?returnTo=%2Fsettings').toString(),
      scopes: 'openid email profile',
      queryParams: const {'prompt': 'select_account'},
    );
    if (!launched) throw StateError('Browser unavailable.');
    return;
  }
  final value = globalContext['hyperGoogleOAuth'];
  if (value == null) throw StateError('Extension OAuth bridge unavailable.');
  final bridge = _GoogleOAuthBridge(value as JSObject);
  final redirect = Uri.parse(bridge.redirectUrl());
  final response = await client.auth.getOAuthSignInUrl(
    provider: OAuthProvider.google,
    redirectTo: redirect.toString(),
    scopes: 'openid email profile',
    queryParams: const {'prompt': 'select_account'},
  );
  final callback = (await bridge.authorize(response.url.toJS).toDart).toDart;
  final code = googleOAuthCallbackCode(Uri.parse(callback), redirect);
  await client.auth.exchangeCodeForSession(code);
}

extension type _GoogleOAuthBridge(JSObject _) implements JSObject {
  external String redirectUrl();
  external JSPromise<JSString> authorize(JSString url);
}
