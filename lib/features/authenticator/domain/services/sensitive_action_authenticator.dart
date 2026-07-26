enum SensitiveActionAuthenticationResult {
  success,
  canceled,
  unavailable,
  failed,
}

/// Fresh OS authentication boundary for actions that disclose TOTP secrets.
abstract interface class SensitiveActionAuthenticator {
  Future<SensitiveActionAuthenticationResult> authenticateForExport();
}
