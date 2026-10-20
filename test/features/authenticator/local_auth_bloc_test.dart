import 'dart:async';
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

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    test(
      'configured lock stays locked when support is false: $platform',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final bloc = LocalAuthBloc(
          auth: _FakeLocalAuthentication(supported: false),
          sharedPreferences: await SharedPreferences.getInstance(),
        );
        addTearDown(bloc.close);
        final next = bloc.stream.first;
        bloc.add(CheckLocalAuth());
        expect(await next, isA<LocalAuthError>());
        expect(bloc.sharedPreferences.getBool('biometric_enabled'), isTrue);
      },
    );
  }

  test('disabled lock does not require an available plugin', () async {
    SharedPreferences.setMockInitialValues({'biometric_enabled': false});
    final bloc = LocalAuthBloc(
      auth: _FakeLocalAuthentication(throwOnSupportCheck: true),
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    addTearDown(bloc.close);
    final next = bloc.stream.first;
    bloc.add(CheckLocalAuth());
    expect(await next, isA<LocalAuthSuccess>());
  });

  test(
    'authentication finishing after background reset cannot unlock',
    () async {
      final completion = Completer<bool>();
      final auth = _FakeLocalAuthentication(completion: completion);
      final bloc = LocalAuthBloc(
        auth: auth,
        sharedPreferences: await SharedPreferences.getInstance(),
      );
      addTearDown(bloc.close);
      var next = bloc.stream.first;
      bloc.add(CheckLocalAuth());
      await next;
      bloc.add(Authenticate());
      await auth.started.future;
      bloc.add(ResetAuthStatus());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<LocalAuthRequired>());
      completion.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<LocalAuthRequired>());
    },
  );

  for (final code in [
    LocalAuthExceptionCode.userCanceled,
    LocalAuthExceptionCode.systemCanceled,
    LocalAuthExceptionCode.noBiometricsEnrolled,
  ]) {
    test('authentication $code never unlocks', () async {
      final bloc = LocalAuthBloc(
        auth: _FakeLocalAuthentication(authError: code),
        sharedPreferences: await SharedPreferences.getInstance(),
      );
      addTearDown(bloc.close);
      final next = bloc.stream.first;
      bloc.add(Authenticate());
      expect(await next, isNot(isA<LocalAuthSuccess>()));
    });
  }

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

    final expectation = expectLater(
      bloc.stream,
      emits(
        isA<LocalAuthError>()
            .having(
              (state) => state.message,
              'message',
              'Không thể kiểm tra khóa ứng dụng. Hãy thử lại.',
            )
            .having(
              (state) => state.message,
              'không lộ exception',
              isNot(contains('TEST_ONLY')),
            ),
      ),
    );
    bloc.add(CheckLocalAuth());

    await expectation;
  });
}

class _FakeLocalAuthentication extends LocalAuthentication {
  final bool authenticateResult;
  final bool throwOnSupportCheck;
  final bool supported;
  final Completer<bool>? completion;
  final LocalAuthExceptionCode? authError;
  final started = Completer<void>();

  _FakeLocalAuthentication({
    this.authenticateResult = false,
    this.throwOnSupportCheck = false,
    this.supported = true,
    this.completion,
    this.authError,
  });

  @override
  Future<bool> get canCheckBiometrics async {
    if (throwOnSupportCheck) throw StateError('TEST_ONLY support failure');
    return supported;
  }

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    if (!started.isCompleted) started.complete();
    if (authError != null) throw LocalAuthException(code: authError!);
    return completion?.future ?? authenticateResult;
  }
}
