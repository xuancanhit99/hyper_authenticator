import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/lock_screen_page.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'lock screen responsive và truy cập được ở ${themeMode.name} text scale 200%',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({'biometric_enabled': true});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final auth = _FakeLocalAuthentication();
        final bloc = LocalAuthBloc(
          auth: auth,
          sharedPreferences: await SharedPreferences.getInstance(),
        );
        addTearDown(bloc.close);
        final required = bloc.stream.firstWhere(
          (state) => state is LocalAuthRequired,
        );
        bloc.add(CheckLocalAuth());
        await required;

        await tester.pumpWidget(
          BlocProvider.value(
            value: bloc,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const LockScreenPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Ứng dụng đang được khóa'), findsOneWidget);
        expect(find.text('Mở khóa'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        final automaticCalls = auth.authenticateCalls;
        final unlockButton = find.widgetWithText(FilledButton, 'Mở khóa');
        await tester.ensureVisible(unlockButton);
        await tester.pump();
        await tester.tap(unlockButton);
        await tester.pumpAndSettle();
        expect(auth.authenticateCalls, automaticCalls + 1);
        semantics.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}

class _FakeLocalAuthentication extends LocalAuthentication {
  int authenticateCalls = 0;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    authenticateCalls++;
    return false;
  }
}
