import 'dart:convert';

/// Public configuration that is safe to embed in a client artifact.
///
/// This validator deliberately accepts only Supabase publishable keys or the
/// legacy `anon` JWT. It never includes a key value in an error message.
class PublicRuntimeConfig {
  final Uri supabaseUrl;
  final String supabasePublishableKey;
  final Uri? passwordRecoveryUrl;

  const PublicRuntimeConfig._({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.passwordRecoveryUrl,
  });

  static PublicRuntimeConfig validate({
    required String supabaseUrl,
    required String supabasePublishableKey,
    required String passwordRecoveryUrl,
    required bool allowInsecurePlaintextSync,
    required bool releaseMode,
  }) {
    final parsedSupabaseUrl = _parseHttpsUrl(
      name: 'SUPABASE_URL',
      value: supabaseUrl,
      originOnly: true,
    );

    if (!_isPublishableKey(supabasePublishableKey) &&
        !_isLegacyAnonKey(supabasePublishableKey)) {
      throw StateError(
        'SUPABASE_PUBLISHABLE_KEY phải là sb_publishable hoặc legacy anon key',
      );
    }

    final parsedRecoveryUrl = passwordRecoveryUrl.isEmpty
        ? null
        : _parseHttpsUrl(
            name: 'PASSWORD_RECOVERY_URL',
            value: passwordRecoveryUrl,
            originOnly: false,
          );

    if (releaseMode && parsedRecoveryUrl == null) {
      throw StateError('Release bắt buộc cấu hình PASSWORD_RECOVERY_URL');
    }
    if (allowInsecurePlaintextSync) {
      throw StateError(
        'ALLOW_INSECURE_PLAINTEXT_SYNC đã bị loại bỏ và phải luôn là false',
      );
    }

    return PublicRuntimeConfig._(
      supabaseUrl: parsedSupabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
      passwordRecoveryUrl: parsedRecoveryUrl,
    );
  }

  static Uri _parseHttpsUrl({
    required String name,
    required String value,
    required bool originOnly,
  }) {
    final parsed = Uri.tryParse(value);
    final invalidOriginPath =
        originOnly &&
        parsed != null &&
        parsed.path.isNotEmpty &&
        parsed.path != '/';
    if (value.isEmpty ||
        value.trim() != value ||
        parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.userInfo.isNotEmpty ||
        invalidOriginPath) {
      final scope = originOnly ? ' HTTPS origin' : ' URL HTTPS';
      throw StateError(
        '$name phải là$scope không chứa user info, query hoặc fragment',
      );
    }
    return parsed;
  }

  static bool _isPublishableKey(String value) {
    return RegExp(
      r'^sb_publishable_[A-Za-z0-9_-]{22}_[A-Za-z0-9_-]{8}$',
    ).hasMatch(value);
  }

  static bool _isLegacyAnonKey(String value) {
    final parts = value.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      return false;
    }
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map<String, dynamic> && payload['role'] == 'anon';
    } on FormatException {
      return false;
    }
  }
}
