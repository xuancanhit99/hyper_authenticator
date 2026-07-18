import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('khóa đã bật yêu cầu local authentication khi khởi động', () async {
    final bloc = LocalAuthBloc(
      auth: _FakeLocalAuthentication(),
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    addTearDown(bloc.close);

    final expectation = expectLater(
      bloc.stream,
      emits(isA<LocalAuthRequired>()),
    );
    bloc.add(CheckLocalAuth());

    await expectation;
  });

  test('rời foreground reset success và resume yêu cầu unlock lại', () async {
    final auth = _FakeLocalAuthentication(authenticateResult: true);
    final bloc = LocalAuthBloc(
      auth: auth,
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    addTearDown(bloc.close);

    final expectation = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<LocalAuthRequired>(),
        isA<LocalAuthSuccess>(),
        isA<LocalAuthInitial>(),
        isA<LocalAuthRequired>(),
      ]),
    );
    bloc
      ..add(CheckLocalAuth())
      ..add(Authenticate())
      ..add(ResetAuthStatus())
      ..add(CheckLocalAuth());

    await expectation;
  });

  test('plugin error không bypass khóa đã cấu hình', () async {
    final bloc = LocalAuthBloc(
      auth: _FakeLocalAuthentication(throwOnSupportCheck: true),
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    addTearDown(bloc.close);

    final expectation = expectLater(bloc.stream, emits(isA<LocalAuthError>()));
    bloc.add(CheckLocalAuth());

    await expectation;
  });
}

class _FakeLocalAuthentication extends LocalAuthentication {
  final bool authenticateResult;
  final bool throwOnSupportCheck;

  _FakeLocalAuthentication({
    this.authenticateResult = false,
    this.throwOnSupportCheck = false,
  });

  @override
  Future<bool> get canCheckBiometrics async {
    if (throwOnSupportCheck) throw StateError('TEST_ONLY support failure');
    return true;
  }

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async => authenticateResult;
}
