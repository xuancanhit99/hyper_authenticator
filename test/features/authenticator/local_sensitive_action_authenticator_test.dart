import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/data/services/local_sensitive_action_authenticator.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/sensitive_action_authenticator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'fresh auth dùng sensitive transaction và không sống qua background',
    () async {
      final localAuth = _FakeLocalAuthentication(authenticateResult: true);
      final authenticator = LocalSensitiveActionAuthenticator(localAuth);

      final result = await authenticator.authenticateForExport();

      expect(result, SensitiveActionAuthenticationResult.success);
      expect(localAuth.authenticateCalls, 1);
      expect(localAuth.lastSensitiveTransaction, isTrue);
      expect(localAuth.lastPersistAcrossBackgrounding, isFalse);
      expect(localAuth.lastBiometricOnly, isFalse);
    },
  );

  test('user cancel không bị chuyển thành success', () async {
    final authenticator = LocalSensitiveActionAuthenticator(
      _FakeLocalAuthentication(
        exception: const LocalAuthException(
          code: LocalAuthExceptionCode.userCanceled,
        ),
      ),
    );

    expect(
      await authenticator.authenticateForExport(),
      SensitiveActionAuthenticationResult.canceled,
    );
  });

  test('thiết bị không có credential fail closed', () async {
    final authenticator = LocalSensitiveActionAuthenticator(
      _FakeLocalAuthentication(deviceSupported: false, canCheck: false),
    );

    expect(
      await authenticator.authenticateForExport(),
      SensitiveActionAuthenticationResult.unavailable,
    );
  });
}

class _FakeLocalAuthentication extends LocalAuthentication {
  _FakeLocalAuthentication({
    this.authenticateResult = false,
    this.deviceSupported = true,
    this.canCheck = true,
    this.exception,
  });

  final bool authenticateResult;
  final bool deviceSupported;
  final bool canCheck;
  final LocalAuthException? exception;
  int authenticateCalls = 0;
  bool? lastBiometricOnly;
  bool? lastSensitiveTransaction;
  bool? lastPersistAcrossBackgrounding;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    authenticateCalls++;
    lastBiometricOnly = biometricOnly;
    lastSensitiveTransaction = sensitiveTransaction;
    lastPersistAcrossBackgrounding = persistAcrossBackgrounding;
    if (exception case final error?) throw error;
    return authenticateResult;
  }
}
