import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // For logout
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart'; // Will create this
import 'package:hyper_authenticator/injection_container.dart'; // For accessing bloc

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (_) =>
              sl<SettingsBloc>()..add(LoadSettings()), // Load initial settings
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, state) {
            bool isBiometricEnabled = false;
            bool canCheckBiometrics =
                false; // Check if device supports biometrics

            if (state is SettingsLoaded) {
              isBiometricEnabled = state.isBiometricEnabled;
              canCheckBiometrics = state.canCheckBiometrics;
            } else if (state is SettingsLoading) {
              // Optionally show loading indicator while checking biometrics support
              return const Center(child: CircularProgressIndicator());
            }
            // Handle SettingsError state if needed

            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // --- Biometric Login Section ---
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('Biometric Login'),
                  subtitle: Text(
                    canCheckBiometrics
                        ? 'Use FaceID / Fingerprint to unlock the app'
                        : 'Biometrics not available on this device',
                  ),
                  trailing:
                      canCheckBiometrics
                          ? Switch(
                            value: isBiometricEnabled,
                            onChanged: (value) {
                              context.read<SettingsBloc>().add(
                                ToggleBiometric(isEnabled: value),
                              );
                            },
                          )
                          : null, // Disable switch if not supported
                  onTap:
                      canCheckBiometrics
                          ? () {
                            // Allow tapping row to toggle
                            context.read<SettingsBloc>().add(
                              ToggleBiometric(isEnabled: !isBiometricEnabled),
                            );
                          }
                          : null,
                ),
                const Divider(),

                // --- Account Section ---
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    // Show confirmation dialog before logging out
                    showDialog(
                      context: context,
                      builder:
                          (dialogContext) => AlertDialog(
                            title: const Text('Confirm Logout'),
                            content: const Text(
                              'Are you sure you want to log out?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext); // Close dialog
                                  context.read<AuthBloc>().add(
                                    AuthSignOutRequested(), // Removed const
                                  );
                                  // Router redirect logic will handle navigation to login
                                },
                                child: const Text(
                                  'Logout',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                    );
                  },
                ),
                const Divider(),

                // Add other settings here later
              ],
            );
          },
        ),
      ),
    );
  }
}
