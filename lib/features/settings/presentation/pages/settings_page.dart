import 'dart:async'; // Added for StreamSubscription

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'; // For logout
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart'; // Added
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Added
import 'package:hyper_authenticator/injection_container.dart';
import 'package:intl/intl.dart'; // Added for date formatting
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart'; // Import UserEntity
import 'package:hyper_authenticator/core/theme/theme_provider.dart'; // Import ThemeProvider
import 'package:hyper_authenticator/core/constants/app_colors.dart'; // Added for _SyncSection

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
        appBar: AppBar(
          backgroundColor:
              Theme.of(context).scaffoldBackgroundColor, // Set background color
          elevation: 0, // Remove shadow
          title: const Text('Settings'),
          actions: [
            // Use Consumer<ThemeProvider> for theme switching UI
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                IconData iconData;
                switch (themeProvider.themeMode) {
                  case ThemeMode.light:
                    iconData = Icons.light_mode_outlined;
                    break;
                  case ThemeMode.dark:
                    iconData = Icons.dark_mode_outlined;
                    break;
                  case ThemeMode.system:
                  default: // Default to system icon
                    iconData = Icons.brightness_auto_outlined;
                    break;
                }
                return PopupMenuButton<ThemeMode>(
                  icon: Icon(iconData),
                  tooltip: 'Change Theme',
                  onSelected: (ThemeMode result) {
                    // Use ThemeProvider to set the theme
                    Provider.of<ThemeProvider>(
                      context,
                      listen: false,
                    ).setThemeMode(result);
                  },
                  itemBuilder:
                      (BuildContext context) => <PopupMenuEntry<ThemeMode>>[
                        const PopupMenuItem<ThemeMode>(
                          value: ThemeMode.system,
                          child: ListTile(
                            leading: Icon(Icons.brightness_auto_outlined),
                            title: Text('System'),
                          ),
                        ),
                        const PopupMenuItem<ThemeMode>(
                          value: ThemeMode.light,
                          child: ListTile(
                            leading: Icon(Icons.light_mode_outlined),
                            title: Text('Light'),
                          ),
                        ),
                        const PopupMenuItem<ThemeMode>(
                          value: ThemeMode.dark,
                          child: ListTile(
                            leading: Icon(Icons.dark_mode_outlined),
                            title: Text('Dark'),
                          ),
                        ),
                      ],
                );
              },
            ),
          ],
        ),
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
            builder: (context, settingsState) {
              final isDarkMode =
                  Theme.of(context).brightness == Brightness.dark;
              // Renamed state to settingsState
              // Access AuthBloc state to get user info
              final authState = context.watch<AuthBloc>().state;
              UserEntity? currentUser;
              if (authState is AuthAuthenticated) {
                currentUser = authState.user;
              }

              bool isBiometricEnabled = false;
              bool canCheckBiometrics = false;

              if (settingsState is SettingsLoaded) {
                isBiometricEnabled = settingsState.isBiometricEnabled;
                canCheckBiometrics = settingsState.canCheckBiometrics;
              } else if (settingsState is SettingsLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              // Handle SettingsError state if needed

              return ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                children: [
                  // --- User Info Card ---
                  if (currentUser !=
                      null) // Only show card if user is logged in
                    Card(
                      color:
                          isDarkMode
                              ? AppColors
                                  .cCardDarkColor // Use custom dark color
                              : Theme.of(
                                context,
                              ).cardColor, // Use default theme color for light mode
                      margin: const EdgeInsets.only(
                        bottom: 16.0,
                      ), // Add margin below the card
                      child: ListTile(
                        leading: CircleAvatar(
                          // Simple avatar
                          // backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            // Use first letter of name for avatar
                            currentUser.name?.isNotEmpty == true
                                ? currentUser.name![0].toUpperCase()
                                : (currentUser.email?.isNotEmpty == true
                                    ? currentUser.email![0].toUpperCase()
                                    : '?'), // Fallback to email initial
                            // style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                        ),
                        title: Text(
                          // Display name as title
                          currentUser.name ??
                              'N/A', // Use name, fallback to N/A
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          currentUser.email ?? 'No email',
                        ), // Display email as subtitle
                        // subtitle: Text(currentUser.email ?? 'No email'), // Remove subtitle or display something else
                      ),
                    ),
                  // --- Settings Card ---
                  Card(
                    color:
                        isDarkMode
                            ? AppColors
                                .cCardDarkColor // Use custom dark color
                            : Theme.of(
                              context,
                            ).cardColor, // Use default theme color for light mode
                    margin: const EdgeInsets.only(
                      bottom: 16.0,
                    ), // Add margin below the card
                    child: Column(
                      // Wrap settings in a Column inside the Card
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
                                    activeTrackColor:
                                        Colors
                                            .green, // Changed to activeTrackColor
                                    onChanged: (value) {
                                      context.read<SettingsBloc>().add(
                                        ToggleBiometric(isEnabled: value),
                                      );
                                    },
                                  )
                                  : null,
                          // Disable switch if not supported
                          onTap:
                              canCheckBiometrics
                                  ? () {
                                    // Allow tapping row to toggle
                                    context.read<SettingsBloc>().add(
                                      ToggleBiometric(
                                        isEnabled: !isBiometricEnabled,
                                      ),
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
                                        onPressed:
                                            () => Navigator.pop(dialogContext),
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
                        // const Divider(),
                      ],
                    ),
                  ),
                  // Add other settings here later (outside the card)
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
  StreamSubscription<AuthState>? _authSubscription;

  // Removed local _isSyncEnabled state. Will rely solely on SyncBloc state.

  @override
  void initState() {
    super.initState();
    // Listen to AuthBloc state changes
    _authSubscription = context.read<AuthBloc>().stream.listen((authState) {
      // Trigger check only when authenticated and widget is mounted
      if (mounted && authState is AuthAuthenticated) {
        print(
          "[_SyncSectionState] AuthAuthenticated detected, dispatching CheckSyncStatus.",
        );
        context.read<SyncBloc>().add(CheckSyncStatus());
      } else {
        print(
          "[_SyncSectionState] Auth state is not AuthAuthenticated (${authState.runtimeType}), not dispatching CheckSyncStatus.",
        );
      }
    });

    // Also trigger an initial check if already authenticated when widget builds
    // (Handles cases where settings page is visited after initial auth)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final currentAuthState = context.read<AuthBloc>().state;
        if (currentAuthState is AuthAuthenticated) {
          print(
            "[_SyncSectionState] Already authenticated on build, dispatching CheckSyncStatus.",
          );
          // Request initial status including enabled state and last sync time
          context.read<SyncBloc>().add(CheckSyncStatus());
          // Initial CheckSyncStatus is dispatched. UI will update via BlocBuilder.
        }
      }
    });
    // No need for a separate listener, BlocBuilder handles UI updates based on state.
  }

  @override
  void dispose() {
    _authSubscription?.cancel(); // Cancel subscription on dispose
    super.dispose();
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
        // Determine state variables directly from SyncBloc's state
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        bool isCurrentlySyncEnabled = false; // Default to false
        DateTime? lastSyncTime;
        bool hasRemoteData = false;
        bool isSyncing = state is SyncInProgress;
        String syncProgressMessage = '';

        if (state is SyncStatusChecked) {
          isCurrentlySyncEnabled = state.isSyncEnabled;
          lastSyncTime = state.lastSyncTime;
          hasRemoteData = state.hasRemoteData;
        } else if (state is SyncFailure) {
          isCurrentlySyncEnabled = state.isSyncEnabled;
          // Potentially retrieve last known sync time if needed, but error state takes precedence
        } else if (state is SyncSuccess) {
          // After success, we might not know the enabled status without another check,
          // but we can assume it's enabled if a sync just happened.
          // Let's rely on the subsequent CheckSyncStatus triggered by the BLoC.
          // For immediate UI feedback, we can infer:
          isCurrentlySyncEnabled = true; // Assume enabled after success
          lastSyncTime = state.lastSyncTime;
        } else if (state is SyncInProgress) {
          syncProgressMessage = state.message;
          // Infer enabled status from previous state if possible, or default
          // This requires more complex state management or passing previous state.
          // Simplification: Assume it's enabled if syncing is in progress.
          isCurrentlySyncEnabled = true;
        }
        // If state is SyncInitial, isCurrentlySyncEnabled remains false.

        Widget statusWidget = const Text(
          'Sync status unknown.',
        ); // Default status

        if (state is SyncInitial ||
            state is SyncInProgress &&
                state.message == 'Checking sync status...') {
          statusWidget = Row(
            // Keep the checking status indicator
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16, // Slightly smaller
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Checking status...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        } else if (state is SyncStatusChecked) {
          // isCurrentlySyncEnabled, lastSyncTime, hasRemoteData already set above

          // Display last sync time if available and sync is enabled
          if (isCurrentlySyncEnabled && lastSyncTime != null) {
            final formattedTime = DateFormat.yMd().add_jm().format(
              lastSyncTime,
            );
            statusWidget = Text(
              'Last sync: $formattedTime',
              style: Theme.of(context).textTheme.bodySmall,
            );
          } else if (isCurrentlySyncEnabled) {
            statusWidget = Text(
              'Sync enabled. Ready to sync.', // Or 'No previous sync found.'
              style: Theme.of(context).textTheme.bodySmall,
            );
          } else {
            statusWidget = Text(
              'Sync is disabled.',
              style: Theme.of(context).textTheme.bodySmall,
            );
          }

          // Actions (Sync Now button) are only relevant if sync is enabled
          // No separate actions list needed anymore
        } else if (state is SyncFailure) {
          statusWidget = Row(
            // Show error with a retry button inline
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                // Allow text to wrap if needed
                child: Text(
                  'Error: ${state.message}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Optionally add a small retry button here if desired
              // TextButton(onPressed: () => context.read<SyncBloc>().add(CheckSyncStatus()), child: Text('Retry'))
            ],
          );
        } else if (state is SyncSuccess) {
          // isCurrentlySyncEnabled, lastSyncTime already set above
          if (isCurrentlySyncEnabled && lastSyncTime != null) {
            final formattedTime = DateFormat.yMd().add_jm().format(
              lastSyncTime,
            );
            statusWidget = Text(
              'Last sync: $formattedTime',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.green,
              ), // Indicate success
            );
          } else if (isCurrentlySyncEnabled) {
            statusWidget = Text(
              'Sync successful.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.green),
            );
          }
        }
        // Handle other states like SyncInitial if needed

        // Determine if "Sync Now" should be enabled
        final bool canSyncNow =
            isCurrentlySyncEnabled &&
            !isSyncing &&
            accountsState is AccountsLoaded;

        return Column(
          mainAxisSize: MainAxisSize.min, // Take minimum vertical space
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync Accounts'),
              subtitle:
                  isSyncing &&
                          syncProgressMessage !=
                              'Checking sync status...' // Show progress only during actual sync
                      ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            syncProgressMessage, // Show specific progress message
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                      : statusWidget, // Otherwise show the determined status
              trailing: IconButton(
                iconSize: 32.0, // Increased icon size
                icon: Icon(
                  isCurrentlySyncEnabled
                      ? Icons
                          .cloud_done // Kept user's icon
                      : Icons
                          .cloud_off_outlined, // Use filled cloud when enabled
                  color:
                      isDarkMode
                          ? AppColors.cDarkIconBg
                          : AppColors.cLightIconBg,
                ),
                tooltip:
                    isCurrentlySyncEnabled ? 'Disable Sync' : 'Enable Sync',
                onPressed: () {
                  // Dispatch event to BLoC to toggle the state
                  context.read<SyncBloc>().add(
                    ToggleSyncEnabled(
                      isEnabled: !isCurrentlySyncEnabled,
                    ), // Send the opposite of the current state
                  );
                  // UI will update automatically via BlocBuilder when state changes
                },
              ), // Removed custom contentPadding
            ),
            // Conditionally display the "Sync Now" button and last sync time
            if (isCurrentlySyncEnabled)
              Padding(
                padding: const EdgeInsets.only(
                  left: 72.0, // Indent to align with ListTile content
                  right: 16.0,
                  bottom: 8.0,
                  top: 0, // Reduce top padding
                ),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync Now'),
                  onPressed:
                      canSyncNow
                          ? () {
                            // Show confirmation dialog before syncing
                            showDialog(
                              context: context,
                              builder:
                                  (dialogContext) => AlertDialog(
                                    title: const Text('Choose Sync Option'),
                                    // Use content to explain the options briefly or remove if buttons are clear enough
                                    content: SingleChildScrollView(
                                      // Use SingleChildScrollView if content might overflow
                                      child: ListBody(
                                        children: <Widget>[
                                          Text(
                                            'Select how you want to synchronize your accounts:',
                                          ),
                                          SizedBox(
                                            height: 16,
                                          ), // Add some spacing
                                          _buildSyncOption(
                                            context: dialogContext,
                                            // Pass dialog context
                                            title: 'Sync and Merge',
                                            description:
                                                'Adds new local/cloud accounts, updates existing ones based on cloud data, then uploads the merged result.',
                                            icon: Icons.merge_type,
                                            color: AppColors.cPrimaryColor,
                                            onPressed: () {
                                              Navigator.pop(
                                                dialogContext,
                                              ); // Close dialog
                                              // Dispatch the original SyncNowRequested event for merge logic
                                              context.read<SyncBloc>().add(
                                                SyncNowRequested(
                                                  accountsToUpload:
                                                      currentAccounts,
                                                ),
                                              );
                                            },
                                          ),
                                          SizedBox(height: 12),
                                          _buildSyncOption(
                                            context: dialogContext,
                                            // Pass dialog context
                                            title: 'Sync and Overwrite Cloud',
                                            description:
                                                'Replaces ALL cloud data with your current local data. Use with caution!',
                                            icon: Icons.cloud_upload_outlined,
                                            // Or Icons.warning_amber_rounded
                                            color: Colors.red,
                                            onPressed: () {
                                              Navigator.pop(
                                                dialogContext,
                                              ); // Close dialog
                                              // Dispatch the new event for overwrite logic
                                              context.read<SyncBloc>().add(
                                                SyncOverwriteCloudRequested(
                                                  // Use the new event
                                                  accountsToUpload:
                                                      currentAccounts,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(dialogContext),
                                        child: const Text('Cancel'),
                                      ),
                                    ],
                                  ),
                            );
                          }
                          : null, // Disable if not enabled, syncing, or no accounts
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Helper widget to build sync option buttons in the dialog
  Widget _buildSyncOption({
    required BuildContext context, // Dialog context
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      icon: Icon(icon, color: color, size: 20),
      label: Column(
        // Removed Padding widget
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Take minimum space
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
            ), // Smaller font for description
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.5)),
        alignment: Alignment.centerLeft,
        // Align icon and text to the left
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.all(12.0), // Added padding here
      ),
      onPressed: onPressed,
    );
  }
}
