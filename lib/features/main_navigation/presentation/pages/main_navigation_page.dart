import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';

class MainNavigationPage extends StatelessWidget {
  static const _accountsBranchIndex = 0;
  static const accountsTabKey = Key('main_navigation_accounts_tab');
  static const settingsTabKey = Key('main_navigation_settings_tab');
  static const navigationBarKey = Key('main_navigation_bar');
  static const navigationRailKey = Key('main_navigation_rail');
  static const navigationAnimationDuration = Duration(milliseconds: 200);
  static const navigationRailBreakpoint = 900.0;

  final StatefulNavigationShell navigationShell;

  const MainNavigationPage({required this.navigationShell, super.key});

  void _onItemTapped(int index) {
    navigationShell.goBranch(
      index,
      // Startup/lock là overlay root nhưng nằm trong history của Accounts
      // branch để giữ shell sống qua lifecycle redirect. Khi app resume về
      // Settings, history đã lưu của branch 0 có thể vẫn là `/startup`; restore
      // history đó sẽ lập tức redirect ngược về Settings. Accounts vì vậy luôn
      // mở initial location, còn các branch khác vẫn giữ state như bình thường.
      initialLocation:
          index == _accountsBranchIndex ||
          index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= navigationRailBreakpoint) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                key: navigationRailKey,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _onItemTapped,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.75,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.shield_outlined, key: accountsTabKey),
                    selectedIcon: Icon(Icons.shield, key: accountsTabKey),
                    label: Text(AppCopy.accounts),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined, key: settingsTabKey),
                    selectedIcon: Icon(Icons.settings, key: settingsTabKey),
                    label: Text(AppCopy.settings),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: navigationShell),
            ],
          ),
        );
      }

      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          key: navigationBarKey,
          animationDuration: navigationAnimationDuration,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const <Widget>[
            NavigationDestination(
              key: accountsTabKey,
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: AppCopy.accounts,
            ),
            NavigationDestination(
              key: settingsTabKey,
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: AppCopy.settings,
            ),
          ],
        ),
      );
    },
  );
}
