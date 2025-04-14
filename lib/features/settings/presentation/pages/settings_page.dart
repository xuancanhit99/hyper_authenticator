import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // For logout
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart'; // Added
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Added
import 'package:hyper_authenticator/injection_container.dart';
import 'package:intl/intl.dart'; // Added for date formatting
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart'; // Added for _SyncSection

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Provide multiple Blocs needed for this page
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<SettingsBloc>()..add(LoadSettings())),
        BlocProvider(
          // Create the SyncBloc instance, but DO NOT add CheckSyncStatus here.
          // The check should be triggered explicitly when the page is viewed or refreshed.
          create: (_) => sl<SyncBloc>(),
        ),
        // AccountsBloc is likely provided higher up, but ensure it's accessible
        // If not provided higher up, add: BlocProvider.value(value: sl<AccountsBloc>()),
      ],
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: BlocListener<SyncBloc, SyncState>(
          // Listen for sync success/failure messages
          listener: (context, state) {
            if (state is SyncSuccess) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.green,
                  ),
                );
            } else if (state is SyncFailure) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.red,
                  ),
                );
            }
          },
          child: BlocBuilder<SettingsBloc, SettingsState>(
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

                  // --- Sync Accounts Section ---
                  _SyncSection(), // Use the dedicated widget
                  const Divider(),

                  // --- Account Section (Moved to bottom) ---
                  // Add other settings here later

                  // --- Logout Section ---
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
                                    Navigator.pop(
                                      dialogContext,
                                    ); // Close dialog
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
      ),
    );
  }
}

// Widget dedicated to the Sync section UI and logic
class _SyncSection extends StatefulWidget {
  @override
  _SyncSectionState createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  @override
  void initState() {
    super.initState();
    // Dispatch CheckSyncStatus when the widget is first initialized
    // Ensure the bloc is available before adding the event
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Check if the widget is still mounted
        context.read<SyncBloc>().add(CheckSyncStatus());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Access AccountsBloc to get the current list for upload
    final accountsState = context.watch<AccountsBloc>().state;
    final currentAccounts =
        (accountsState is AccountsLoaded)
            ? accountsState.accounts
            : <AuthenticatorAccount>[];

    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        Widget statusWidget;
        List<Widget> actions = [];

        if (state is SyncInitial ||
            state is SyncInProgress && state is! SyncStatusChecked) {
          statusWidget = const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Checking sync status...'),
            ],
          );
        } else if (state is SyncStatusChecked) {
          // Build status text based on remote data and last sync time
          List<String> statusParts = [];
          // if (state.hasRemoteData) {
          //   statusParts.add('Remote data found.');
          // } else {
          //   statusParts.add('No remote data found.');
          // }

          // Use the renamed state property: lastUploadTime
          if (state.lastUploadTime != null) {
            // Format the time nicely
            final formattedTime = DateFormat.yMd().add_jm().format(
              state.lastUploadTime!, // Use renamed property
            );
            // Update the display text
            statusParts.add('Last upload: $formattedTime');
          }

          final statusText = statusParts.join(' '); // Join parts with a space

          statusWidget = Text(
            statusText,
            style: Theme.of(context).textTheme.bodySmall,
          );

          // Enable buttons only when not syncing and accounts are loaded
          final bool canSync = accountsState is AccountsLoaded;
          final bool isSyncing = context.select(
            (SyncBloc bloc) => bloc.state is SyncInProgress,
          );

          actions = [
            ElevatedButton.icon(
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Upload'),
              onPressed:
                  (!isSyncing && canSync && currentAccounts.isNotEmpty)
                      ? () {
                        // Check if remote data exists before uploading
                        if (state is SyncStatusChecked && state.hasRemoteData) {
                          // Show warning dialog
                          showDialog(
                            context: context,
                            builder:
                                (dialogContext) => AlertDialog(
                                  title: const Text('Confirm Upload'),
                                  content: const Text(
                                    'Remote data already exists. Uploading will overwrite it with your current local data.\n\nConsider Downloading first if other devices might have newer data.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(dialogContext),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(
                                          dialogContext,
                                        ); // Close dialog
                                        // Proceed with upload
                                        context.read<SyncBloc>().add(
                                          UploadAccountsRequested(
                                            accountsToUpload: currentAccounts,
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'Upload Anyway',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                          );
                        } else {
                          // No remote data or status not checked yet, upload directly
                          context.read<SyncBloc>().add(
                            UploadAccountsRequested(
                              accountsToUpload: currentAccounts,
                            ),
                          );
                        }
                      }
                      : null, // Disable if syncing, no accounts loaded, or no accounts exist
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
              onPressed:
                  (!isSyncing && state.hasRemoteData)
                      ? () {
                        // Removed the confirmation dialog wrapper as requested.
                        // Dispatch the download event directly.
                        context.read<SyncBloc>().add(
                          DownloadAccountsRequested(),
                        );
                      }
                      : null, // Disable if syncing or no remote data
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ];
        } else if (state is SyncFailure) {
          statusWidget = Text(
            'Sync Error: ${state.message}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
          // Allow retrying status check
          actions = [
            OutlinedButton(
              onPressed: () => context.read<SyncBloc>().add(CheckSyncStatus()),
              child: const Text('Retry Check'),
            ),
          ];
        } else {
          // Default/fallback view (e.g., SyncInitial after an operation)
          statusWidget = const Text('Sync status unknown.');
          actions = [
            OutlinedButton(
              onPressed: () => context.read<SyncBloc>().add(CheckSyncStatus()),
              child: const Text('Check Status'),
            ),
          ];
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync Accounts'),
              subtitle: statusWidget, // Display dynamic status
              contentPadding: const EdgeInsets.only(
                left: 16.0,
                right: 0,
              ), // Adjust padding
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: 72.0,
                  right: 16.0,
                  bottom: 8.0,
                ), // Align with ListTile content
                child: Wrap(spacing: 8.0, runSpacing: 4.0, children: actions),
              ),
          ],
        );
      },
    );
  }
}
