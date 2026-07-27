import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/sensitive_action_authenticator.dart';
import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';

@LazySingleton(as: SensitiveActionAuthenticator)
class LocalSensitiveActionAuthenticator
    implements SensitiveActionAuthenticator {
  const LocalSensitiveActionAuthenticator(this._localAuthentication);

  final LocalAuthentication _localAuthentication;

  @override
  Future<SensitiveActionAuthenticationResult> authenticateForExport() async {
    if (!PlatformCapabilities.supportsLocalAuthentication) {
      return SensitiveActionAuthenticationResult.unavailable;
    }

    try {
      final supported =
          await _localAuthentication.isDeviceSupported() ||
          await _localAuthentication.canCheckBiometrics;
      if (!supported) {
        return SensitiveActionAuthenticationResult.unavailable;
      }
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: 'Xác thực để xuất credential TOTP',
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: false,
      );
      return authenticated
          ? SensitiveActionAuthenticationResult.success
          : SensitiveActionAuthenticationResult.canceled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout =>
          SensitiveActionAuthenticationResult.canceled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          SensitiveActionAuthenticationResult.unavailable,
        _ => SensitiveActionAuthenticationResult.failed,
      };
    } catch (_) {
      return SensitiveActionAuthenticationResult.failed;
    }
  }
}
