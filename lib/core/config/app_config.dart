// lib/core/config/app_config.dart
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:hyper_authenticator/core/config/public_runtime_config.dart';

@lazySingleton
class AppConfig {
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String? passwordRecoveryUrl;

  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.passwordRecoveryUrl,
  });

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

    final validated = PublicRuntimeConfig.validate(
      supabaseUrl: url,
      supabasePublishableKey: publishableKey,
      passwordRecoveryUrl: passwordRecoveryUrlValue,
      allowInsecurePlaintextSync: allowInsecurePlaintextSync,
      releaseMode: kReleaseMode,
    );

    return AppConfig(
      supabaseUrl: validated.supabaseUrl.toString(),
      supabasePublishableKey: validated.supabasePublishableKey,
      passwordRecoveryUrl: validated.passwordRecoveryUrl?.toString(),
    );
  }
}
