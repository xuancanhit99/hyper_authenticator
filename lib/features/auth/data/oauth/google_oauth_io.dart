import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_oauth_loopback.dart';

Future<void> startGoogleSignIn(SupabaseClient client) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'app.hyperz.authenticator://auth/callback',
      scopes: 'openid email profile',
      queryParams: const {'prompt': 'select_account'},
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!launched) throw StateError('Browser unavailable.');
    return; // The SDK's app_links listener completes PKCE and emits the session.
  }
  await completeLoopbackGoogleSignIn(
    authorizationUrl: (redirect) async {
      final response = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: redirect.toString(),
        scopes: 'openid email profile',
        queryParams: const {'prompt': 'select_account'},
      );
      return Uri.parse(response.url);
    },
    launchBrowser: (url) =>
        launchUrl(url, mode: LaunchMode.externalApplication),
    exchangeCode: (code) async {
      await client.auth.exchangeCodeForSession(code);
    },
  );
}
