import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('settings error không đưa dữ liệu preference sai kiểu ra UI', () async {
    SharedPreferences.setMockInitialValues({
      'biometric_enabled': 'TEST_ONLY invalid preference payload',
    });
    final bloc = SettingsBloc(
      sharedPreferences: await SharedPreferences.getInstance(),
      localAuthentication: _SupportedLocalAuthentication(),
    );
    addTearDown(bloc.close);

    bloc.add(LoadSettings());
    final state =
        await bloc.stream.firstWhere((state) => state is SettingsError)
            as SettingsError;

    expect(state.message, 'Không thể tải cài đặt. Hãy thử lại.');
    expect(state.message, isNot(contains('TEST_ONLY')));
  });
}

class _SupportedLocalAuthentication extends LocalAuthentication {
  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> isDeviceSupported() async => true;
}
