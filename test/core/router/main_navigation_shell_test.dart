import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/appearance_style_picker.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/product_info_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets(
    'Accounts không restore startup route cũ sau app-lock resume về Settings',
    (tester) async {
      final localAuthState = ValueNotifier<LocalAuthState>(LocalAuthSuccess());
      addTearDown(localAuthState.dispose);
      final router = _buildLifecycleRedirectRouter(localAuthState);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MainNavigationPage.settingsTabKey));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.settings,
      );

      // Background reset chuyển qua startup overlay. Vì startup thuộc Accounts
      // branch trong topology hiện tại, route này trở thành history đã lưu của
      // branch 0 ngay cả khi UI resume trở lại Settings.
      localAuthState.value = LocalAuthInitial();
      await tester.pumpAndSettle();
      expect(find.text('Startup overlay'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.startup);

      localAuthState.value = LocalAuthSuccess();
      await tester.pumpAndSettle();
      expect(find.text('Settings branch'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.settings,
      );

      await tester.tap(find.byKey(MainNavigationPage.accountsTabKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_AccountsProbe.fieldKey), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.main);
    },
  );

  testWidgets(
    'appearance sheet dùng root navigator và không giữ Settings branch sau resume',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final cubit = ThemeCubit(await SharedPreferences.getInstance());
      addTearDown(cubit.close);
      final router = _buildRouter(settingsHasAppearancePicker: true);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: _ThemeAwareRouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(MainNavigationPage.settingsTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance-picker-tile')));
      await tester.pumpAndSettle();

      final sheetContext = tester.element(find.text('Chọn giao diện'));
      expect(
        identical(
          Navigator.of(sheetContext),
          Navigator.of(sheetContext, rootNavigator: true),
        ),
        isTrue,
      );

      for (final style in const [
        AppStyle.oledDark,
        AppStyle.securityMinimal,
        AppStyle.darkCinema,
      ]) {
        await tester.tap(find.byKey(Key('app-style-option-${style.name}')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('theme-mode-choice-dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme-mode-choice-light')));
      await tester.pumpAndSettle();

      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
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
      await tester.tap(find.byKey(const Key('close-appearance-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('Chọn giao diện'), findsNothing);

      await tester.tap(find.byKey(MainNavigationPage.accountsTabKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_AccountsProbe.fieldKey), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/');
    },
  );

  testWidgets(
    'product info sheet không trở thành history của Settings branch',
    (tester) async {
      final router = _buildRouter(settingsHasProductInfoTile: true);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MainNavigationPage.settingsTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product-info-tile')));
      await tester.pumpAndSettle();

      final sheetContext = tester.element(
        find.byKey(const Key('close-product-info-sheet')),
      );
      expect(
        identical(
          Navigator.of(sheetContext),
          Navigator.of(sheetContext, rootNavigator: true),
        ),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('close-product-info-sheet')));
      await tester.pumpAndSettle();
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

GoRouter _buildRouter({
  bool accountsHasDetailsRoute = false,
  bool settingsHasAppearancePicker = false,
  bool settingsHasProductInfoTile = false,
}) => GoRouter(
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
              builder: (context, state) => Scaffold(
                body: Center(
                  child: settingsHasAppearancePicker
                      ? const AppearanceStylePicker()
                      : settingsHasProductInfoTile
                      ? const ProductInfoTile()
                      : const Text('Settings branch'),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

GoRouter _buildLifecycleRedirectRouter(
  ValueNotifier<LocalAuthState> localAuthState,
) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: localAuthState,
    redirect: (context, state) => AppRedirectPolicy.redirect(
      authState: AuthUnauthenticated(),
      localAuthState: localAuthState.value,
      location: state.matchedLocation,
      returnTo: state.uri.queryParameters['returnTo'],
    ),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainNavigationPage(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.main,
                builder: (context, state) => const _AccountsProbe(),
                routes: [
                  GoRoute(
                    path: 'startup',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const Scaffold(
                      body: Center(child: Text('Startup overlay')),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
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
}

class _ThemeAwareRouterApp extends StatelessWidget {
  const _ThemeAwareRouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeCubit>().state;
    return MaterialApp.router(
      theme: AppTheme.light(state.style),
      darkTheme: AppTheme.dark(state.style),
      themeMode: state.mode,
      routerConfig: router,
      builder: (context, child) =>
          PrivacyShield(child: child ?? const SizedBox.shrink()),
    );
  }
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
