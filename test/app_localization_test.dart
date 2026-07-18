import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/app.dart';
import 'package:hyper_authenticator/core/theme/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app khóa locale tiếng Việt cho UI và Web semantics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Kiểm tra')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(preferences),
        child: MyApp(
          routerConfig: router,
          lightTheme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
        ),
      ),
    );
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('vi'));
    expect(app.supportedLocales, const [Locale('vi')]);
    expect(
      app.localizationsDelegates,
      contains(GlobalMaterialLocalizations.delegate),
    );
    expect(
      Localizations.localeOf(tester.element(find.byType(Scaffold))),
      const Locale('vi'),
    );
  });
}
