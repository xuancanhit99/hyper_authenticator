// lib/core/config/app_config.dart
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AppConfig {
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String? passwordRecoveryUrl;
  final bool allowInsecurePlaintextSync;
  final bool releaseMode;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.passwordRecoveryUrl,
    this.allowInsecurePlaintextSync = false,
    this.releaseMode = kReleaseMode,
  });

  bool get plaintextSyncAvailable => allowInsecurePlaintextSync && !releaseMode;

  @factoryMethod
  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    const allowInsecurePlaintextSync = bool.fromEnvironment(
      'ALLOW_INSECURE_PLAINTEXT_SYNC',
      defaultValue: false,
    );
    const passwordRecoveryUrlValue = String.fromEnvironment(
      'PASSWORD_RECOVERY_URL',
    );

    if (url.isEmpty) {
      throw StateError('Thiếu cấu hình SUPABASE_URL');
    }
    if (publishableKey.isEmpty) {
      throw StateError('Thiếu cấu hình SUPABASE_PUBLISHABLE_KEY');
    }

    final passwordRecoveryUrl = passwordRecoveryUrlValue.isEmpty
        ? null
        : Uri.tryParse(passwordRecoveryUrlValue);
    if (passwordRecoveryUrlValue.isNotEmpty &&
        (passwordRecoveryUrl == null ||
            passwordRecoveryUrl.scheme != 'https' ||
            passwordRecoveryUrl.host.isEmpty ||
            passwordRecoveryUrl.hasQuery ||
            passwordRecoveryUrl.hasFragment ||
            passwordRecoveryUrl.userInfo.isNotEmpty)) {
      throw StateError(
        'PASSWORD_RECOVERY_URL phải là URL HTTPS không chứa query, fragment hoặc user info',
      );
    }

    return AppConfig(
      supabaseUrl: url,
      supabasePublishableKey: publishableKey,
      passwordRecoveryUrl: passwordRecoveryUrl?.toString(),
      allowInsecurePlaintextSync: allowInsecurePlaintextSync,
    );
  }
}
