import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

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

  testWidgets(
    'bottom navigation vẫn phản hồi sau background lâu và privacy shield resume',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final router = _buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              PrivacyShield(child: child ?? const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      expect(find.byKey(privacyShieldOverlayKey), findsOneWidget);

      // Mô phỏng app bị treo/suspend lâu; không có animation hoặc Timer nào
      // được phép giữ lớp chặn interaction sau resumed.
      await tester.pump(const Duration(hours: 2));
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }

      expect(find.byKey(privacyShieldOverlayKey), findsNothing);
      await tester.tap(find.byKey(MainNavigationPage.settingsTabKey));
      await tester.pumpAndSettle();
      expect(find.text('Settings branch'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/settings');

      await tester.tap(find.byKey(MainNavigationPage.accountsTabKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_AccountsProbe.fieldKey), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/');
    },
  );

  testWidgets('reselect tab hiện tại quay về route gốc của branch', (
    tester,
  ) async {
    final router = _buildRouter(accountsHasDetailsRoute: true);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/details');
    await tester.pumpAndSettle();
    expect(find.text('Account details'), findsOneWidget);

    await tester.tap(find.byKey(MainNavigationPage.accountsTabKey));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(_AccountsProbe.fieldKey), findsOneWidget);
  });

  testWidgets('desktop dùng NavigationRail và vẫn đổi branch', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byKey(MainNavigationPage.navigationRailKey), findsOneWidget);
    expect(find.byKey(MainNavigationPage.navigationBarKey), findsNothing);
    await tester.tap(find.byKey(MainNavigationPage.settingsTabKey));
    await tester.pumpAndSettle();
    expect(find.text('Settings branch'), findsOneWidget);
  });
}

GoRouter _buildRouter({bool accountsHasDetailsRoute = false}) => GoRouter(
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
              routes: [
                if (accountsHasDetailsRoute)
                  GoRoute(
                    path: 'details',
                    builder: (context, state) => const Scaffold(
                      body: Center(child: Text('Account details')),
                    ),
                  ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('Settings branch'))),
            ),
          ],
        ),
      ],
    ),
  ],
);

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
