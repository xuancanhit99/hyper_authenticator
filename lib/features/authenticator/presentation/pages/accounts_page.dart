import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/constants/app_colors.dart'; // Import AppColors (needed for Card)
import 'package:hyper_authenticator/core/usecases/usecase.dart'; // For NoParams
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/generate_totp_code.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/utils/logo_service.dart'; // Import LogoService
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart'; // Import Countdown Timer
import 'package:hyper_authenticator/injection_container.dart';
import 'package:go_router/go_router.dart'; // Import GoRouter for navigation
import 'package:hyper_authenticator/core/router/app_router.dart'; // Import AppRoutes
import 'package:hyper_authenticator/core/constants/app_colors.dart'; // Import AppColors

// TODO: Define route for AddAccountPage
// import 'add_account_page.dart'; // Will create this later

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  Timer? _timer;
  int _secondsRemaining = 30;
  // Store current codes to avoid recalculating every build
  final Map<String, String> _currentCodes = {};
  // Inject GenerateTotpCode use case
  final GenerateTotpCode _generateTotpCode = sl<GenerateTotpCode>();

  @override
  void initState() {
    super.initState();
    // Load logo map first (async)
    LogoService.instance.loadLogoMap().then((_) {
      // Then load accounts
      if (mounted) {
        // Check if widget is still mounted after async operation
        context.read<AccountsBloc>().add(LoadAccounts());
      }
    });
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateSecondsRemaining(); // Initial calculation
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateSecondsRemaining();
      // Regenerate codes when timer resets (or close to it)
      if (_secondsRemaining == 30 || _secondsRemaining == 1) {
        // Trigger a state rebuild to update codes if accounts are loaded
        if (mounted && context.read<AccountsBloc>().state is AccountsLoaded) {
          setState(() {});
        }
      } else {
        // Only update timer display if codes don't need regeneration
        setState(() {});
      }
    });
  }

  void _updateSecondsRemaining() {
    final now = DateTime.now();
    final seconds = now.second;
    // Calculate remaining seconds in the 30-second interval
    _secondsRemaining = 30 - (seconds % 30);
  }

  // Function to generate code for a specific account
  Future<String> _getCodeForAccount(AuthenticatorAccount account) async {
    // Pass all necessary parameters from the account to the use case
    final result = await _generateTotpCode(
      GenerateTotpCodeParams(
        secretKey: account.secretKey,
        algorithm: account.algorithm,
        digits: account.digits,
        period: account.period,
      ),
    );
    return result.fold(
      (failure) => "Error", // Handle error display
      (code) => code,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authenticator Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Account',
            onPressed: () {
              // Use GoRouter to navigate to the add account page
              context.push(AppRoutes.addAccount);
            },
          ),
        ],
      ),
      body: BlocConsumer<AccountsBloc, AccountsState>(
        listener: (context, state) {
          if (state is AccountsError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: ${state.message}')));
          }
          // Optional: Show success messages for add/delete if specific states were used
        },
        builder: (context, state) {
          if (state is AccountsLoading || state is AccountsInitial) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is AccountsLoaded) {
            if (state.accounts.isEmpty) {
              // Wrap empty state message with RefreshIndicator as well
              return RefreshIndicator(
                onRefresh: () async {
                  context.read<AccountsBloc>().add(LoadAccounts());
                },
                child: LayoutBuilder(
                  // Use LayoutBuilder to allow scrolling for refresh
                  builder:
                      (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: const Center(
                            child: Text('No accounts added yet. Tap + to add.'),
                          ),
                        ),
                      ),
                ),
              );
            }
            // Build the list view with Pull-to-Refresh inside a Card
            return Card(
              // Wrap with Card
              color:
                  Theme.of(
                    context,
                  ).cardColor, // Use theme card color for light/dark mode compatibility
              margin: const EdgeInsets.all(
                8.0,
              ), // Add some margin around the card
              clipBehavior:
                  Clip.antiAlias, // Optional: Improves corner clipping
              child: RefreshIndicator(
                // Start RefreshIndicator
                onRefresh: () async {
                  // Dispatch LoadAccounts event when pulled
                  context.read<AccountsBloc>().add(LoadAccounts());
                },
                child: ListView.separated(
                  // Change to ListView.separated
                  // Start ListView.separated (child of RefreshIndicator)
                  itemCount: state.accounts.length,
                  separatorBuilder:
                      (context, index) => const Divider(
                        height: 1, // Make divider thin
                        thickness: 1, // Explicit thickness
                        // Optional: Add indent or endIndent if needed
                        // indent: 16.0,
                        // endIndent: 16.0,
                      ),
                  itemBuilder: (context, index) {
                    final account = state.accounts[index];
                    return Dismissible(
                      // Add swipe-to-delete
                      key: Key(account.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) {
                        context.read<AccountsBloc>().add(
                          DeleteAccountRequested(accountId: account.id),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Deleted ${account.issuer} (${account.accountName})',
                            ),
                          ),
                        );
                      },
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: FutureBuilder<String>(
                        // Use future builder to get the code asynchronously
                        future: _getCodeForAccount(account),
                        builder: (context, snapshot) {
                          String displayCode = "------"; // Placeholder
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              snapshot.hasData) {
                            displayCode = snapshot.data!;
                            // Format code with space
                            if (displayCode.length == 6) {
                              displayCode =
                                  '${displayCode.substring(0, 3)} ${displayCode.substring(3)}';
                            }
                            _currentCodes[account.id] =
                                displayCode; // Cache code
                          } else if (_currentCodes.containsKey(account.id)) {
                            displayCode =
                                _currentCodes[account
                                    .id]!; // Use cached code during refresh
                          }

                          final String logoPath = LogoService.instance
                              .getLogoPath(account.issuer);

                          // --- Start New Row Layout ---
                          return InkWell(
                            // Wrap with InkWell for onTap
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text: displayCode.replaceAll(' ', ''),
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Code copied to clipboard'),
                                  duration: Duration(
                                    seconds: 1,
                                  ), // Shorter duration
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ), // Padding for the row
                              child: Row(
                                children: [
                                  // 1. Logo (Square with rounded corners)
                                  // 1. Logo (Cropped with rounded corners) - Updated
                                  SizedBox(
                                    // Constrain the size
                                    width: 40,
                                    height: 40,
                                    child: ClipRRect(
                                      // Apply rounded corners directly to the image
                                      borderRadius: BorderRadius.circular(4.0),
                                      child: Image.asset(
                                        logoPath,
                                        fit:
                                            BoxFit
                                                .contain, // Use contain to avoid stretching
                                        errorBuilder: (
                                          context,
                                          error,
                                          stackTrace,
                                        ) {
                                          // Fallback icon if image fails to load
                                          return Container(
                                            // Add a background for the fallback icon
                                            // color: Colors.grey.shade200, // Optional: Light grey background
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.shield_outlined,
                                              size: 24,
                                              color:
                                                  Colors
                                                      .grey, // Grey icon color
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12), // Spacing
                                  // 2. Issuer / Account Name
                                  Expanded(
                                    // Takes available space
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          account.issuer ?? 'Unknown Issuer',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          account.accountName,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8), // Spacing
                                  // 3. TOTP Code
                                  Text(
                                    displayCode,
                                    style: const TextStyle(
                                      fontSize: 18, // Slightly smaller code?
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5, // Adjust spacing
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ], // Ensure fixed width for digits
                                    ),
                                  ),
                                  const SizedBox(width: 12), // Spacing
                                  // 4. Countdown Timer (Pacman style - no number)
                                  CircularCountdownTimer(
                                    secondsRemaining: _secondsRemaining,
                                    size: 18, // Smaller size?
                                    backgroundColor: Colors.transparent,
                                    progressColor:
                                        Colors.grey, // Set progress color to green
                                    // strokeWidth: 2.0, // Removed as it's no longer a parameter
                                  ),
                                ],
                              ),
                            ),
                          );
                          // --- End New Row Layout ---
                        }, // End FutureBuilder builder
                      ), // End FutureBuilder
                    ); // End Dismissible
                  }, // End itemBuilder
                ), // End ListView.separated
              ), // End RefreshIndicator
            ); // End Card
          } // End of `if (state is AccountsLoaded)`
          // Should not happen if states are handled, but provide fallback
          return const Center(child: Text('An unexpected state occurred.'));
        }, // End BlocConsumer builder
      ), // End BlocConsumer
    ); // End Scaffold
  } // End build method
} // End _AccountsPageState class
