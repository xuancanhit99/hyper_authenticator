import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainNavigationPage extends StatelessWidget {
  static const accountsTabKey = Key('main_navigation_accounts_tab');
  static const settingsTabKey = Key('main_navigation_settings_tab');
  static const navigationAnimationDuration = Duration(milliseconds: 200);

  final StatefulNavigationShell navigationShell;

  const MainNavigationPage({required this.navigationShell, super.key});

  void _onItemTapped(int index) {
    if (navigationShell.currentIndex == index) {
      return;
    }
    navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        animationDuration: navigationAnimationDuration,
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor, // Set background color
        elevation: 0, // Remove shadow
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const <Widget>[
          NavigationDestination(
            key: MainNavigationPage.accountsTabKey,
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Tài khoản',
          ),
          NavigationDestination(
            key: MainNavigationPage.settingsTabKey,
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
