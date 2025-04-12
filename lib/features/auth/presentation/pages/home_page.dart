import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart'; // Added import for AppRoutes
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Get user info from AuthBloc state safely
    final authState = context.watch<AuthBloc>().state;
    String userGreeting = 'Welcome!'; // Default greeting
    if (authState is AuthAuthenticated) {
      userGreeting = 'Welcome, ${authState.user.email ?? 'User'}!';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
        actions: [
          // Only show logout if authenticated
          if (authState is AuthAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () {
                // Show confirmation dialog before signing out
                showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Confirm Sign Out'),
                    content: const Text(
                      'Are you sure you want to sign out?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          // Dispatch sign out event
                          context.read<AuthBloc>().add(
                                AuthSignOutRequested(),
                              );
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        // Added SafeArea
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  userGreeting,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40), // Removed comment marker
              ],
            ),
          ),
        ),
      ),
    );
  }
}
