import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainNavigationPage extends StatelessWidget {
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
      // Reselect tab hiện tại quay về root của branch. Đây là contract chuẩn
      // của StatefulNavigationShell và cũng tự phục hồi branch nếu state route
      // vừa được restore sau lifecycle transition.
      initialLocation: index == navigationShell.currentIndex,
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
                    label: Text('Tài khoản'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined, key: settingsTabKey),
                    selectedIcon: Icon(Icons.settings, key: settingsTabKey),
                    label: Text('Cài đặt'),
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
              label: 'Tài khoản',
            ),
            NavigationDestination(
              key: settingsTabKey,
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Cài đặt',
            ),
          ],
        ),
      );
    },
  );
}
