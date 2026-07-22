import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';

void main() {
  testWidgets(
    'đổi branch cập nhật URL không thay root route và giữ state từng tab',
    (tester) async {
      final router = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                MainNavigationPage(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (context, state) => const _AccountsProbe(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/settings',
                    builder: (context, state) => const Scaffold(
                      body: Center(child: Text('Settings branch')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final navigationBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigationBar.animationDuration,
        MainNavigationPage.navigationAnimationDuration,
      );

      await tester.enterText(
        find.byKey(_AccountsProbe.fieldKey),
        'TEST_ONLY_STATE',
      );
      final shellRouteBefore = ModalRoute.of(
        tester.element(find.byType(MainNavigationPage)),
      );

      await tester.tap(find.byKey(MainNavigationPage.settingsTabKey));
      await tester.pump();

      final shellRouteAfter = ModalRoute.of(
        tester.element(find.byType(MainNavigationPage)),
      );
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      expect(find.text('Settings branch'), findsOneWidget);
      expect(identical(shellRouteAfter, shellRouteBefore), isTrue);
      expect(shellRouteAfter?.animation?.isAnimating, isFalse);
      expect(shellRouteAfter?.animation?.value, 1);

      await tester.tap(find.byKey(MainNavigationPage.accountsTabKey));
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('TEST_ONLY_STATE'), findsOneWidget);
      expect(
        identical(
          ModalRoute.of(tester.element(find.byType(MainNavigationPage))),
          shellRouteBefore,
        ),
        isTrue,
      );
    },
  );

  testWidgets('deep link Settings chọn đúng branch ngay khi bootstrap', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MainNavigationPage(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const _AccountsProbe(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const Scaffold(
                    body: Center(child: Text('Settings branch')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Settings branch'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });
}

class _AccountsProbe extends StatefulWidget {
  const _AccountsProbe();

  static const fieldKey = Key('accounts_state_probe');

  @override
  State<_AccountsProbe> createState() => _AccountsProbeState();
}

class _AccountsProbeState extends State<_AccountsProbe> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextField(key: _AccountsProbe.fieldKey, controller: _controller),
  );
}
