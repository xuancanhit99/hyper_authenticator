import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Import Bloc
import 'package:go_router/go_router.dart'; // Import GoRouter
import 'package:hyper_authenticator/core/router/app_router.dart'; // Import AppRoutes
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart'; // Import LocalAuthBloc
import 'package:hyper_authenticator/features/authenticator/presentation/pages/accounts_page.dart';
import 'package:hyper_authenticator/features/settings/presentation/pages/settings_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  bool _isCheckingLocalAuth = true; // Flag to prevent multiple checks initially

  @override
  void initState() {
    super.initState();
    // Check local auth status when this page is first built
    // Use addPostFrameCallback to ensure BlocProvider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndTriggerLocalAuth();
    });
  }

  void _checkAndTriggerLocalAuth() {
    final localAuthBloc = context.read<LocalAuthBloc>();
    // Check current state first - maybe it was already checked and requires auth
    if (localAuthBloc.state is LocalAuthInitial || _isCheckingLocalAuth) {
      _isCheckingLocalAuth = false; // Mark check as initiated
      localAuthBloc.add(CheckLocalAuth());
    } else if (localAuthBloc.state is LocalAuthRequired) {
      // If already known to be required, navigate to lock screen
      // Use pushReplacement to prevent going back to main nav before unlocking
      context.pushReplacement(AppRoutes.lockScreen);
    }
    // If state is Success or Unavailable, do nothing (already unlocked)
  }

  int _selectedIndex = 0; // Index for the current tab

  // List of pages to navigate between
  static const List<Widget> _widgetOptions = <Widget>[
    AccountsPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Body will display the selected page from _widgetOptions
      body: IndexedStack(
        // Use IndexedStack to keep state of pages
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined), // Or Icons.vpn_key_outlined
            activeIcon: Icon(Icons.shield), // Or Icons.vpn_key
            label: 'Accounts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        // selectedItemColor: Colors.amber[800], // Customize colors if needed
        onTap: _onItemTapped,
      ),
    );
  }
}
