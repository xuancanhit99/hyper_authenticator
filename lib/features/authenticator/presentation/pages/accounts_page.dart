import 'dart:async';
import 'dart:ui'; // For FontFeature

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
  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      _onSearchChanged,
    ); // Add listener for search input
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
    _searchController.removeListener(_onSearchChanged); // Remove listener
    _searchController.dispose(); // Dispose controller
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

  // Listener for search query changes
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            Theme.of(context).scaffoldBackgroundColor, // Set background color
        elevation: 0, // Remove shadow for a flatter look if desired
        title: const Text('Authenticator'),
        actions: [
          // Apply background color directly to IconButton using style
          Padding(
            // Add padding to prevent button touching edge
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.add, size: 20), // Reduced icon size
              color:
                  isDarkMode
                      ? Colors
                          .white // Light icon on dark background
                      : Colors.black87, // Darker icon on light background
              tooltip: 'Add Account',
              style: IconButton.styleFrom(
                backgroundColor:
                    isDarkMode
                        ? AppColors
                            .cDarkIconBg // Dark background for dark mode
                        : AppColors
                            .cLightIconBg, // Light background for light mode
                shape: const CircleBorder(), // Slightly reduced padding for smaller icon
              ),
              onPressed: () {
                context.push(AppRoutes.addAccount);
              },
            ),
          ),
          // Optional: Add a search icon button here if preferred over a persistent text field
          // IconButton(icon: Icon(Icons.search), onPressed: () { /* Toggle search bar visibility */ }),
        ],
      ),
      body: GestureDetector(
        // Wrap with GestureDetector
        onTap: () => FocusScope.of(context).unfocus(), // Unfocus on tap outside
        child: Column(
          // Wrap body content in a Column
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ), // Increased horizontal padding
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search service or app...',
                  prefixIcon: const Icon(Icons.search),
                  // Define consistent border radius
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      12.0,
                    ), // Match Card radius (adjust if needed)
                    borderSide: BorderSide.none,
                  ),
                  // Ensure focused border also uses the same radius and no visible border side
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide:
                        BorderSide.none, // Keep border invisible on focus
                  ),
                  filled: true,
                  fillColor:
                      isDarkMode
                          ? AppColors
                              .cCardDarkColor // Use custom dark color
                          : null, // Use default theme fill color for light mode (or specify one)
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ), // Adjust padding
                  suffixIcon:
                      _searchQuery.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              // _onSearchChanged will be called by the listener
                            },
                          )
                          : null,
                ),
              ),
            ),
            // Account List (Expanded to take remaining space)
            Expanded(
              child: BlocConsumer<AccountsBloc, AccountsState>(
                listener: (context, state) {
                  if (state is AccountsError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${state.message}')),
                    );
                  }
                  // Optional: Show success messages for add/delete if specific states were used
                },
                builder: (context, state) {
                  if (state is AccountsLoading || state is AccountsInitial) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is AccountsLoaded) {
                    // Filter accounts based on search query
                    final List<AuthenticatorAccount> filteredAccounts =
                        state.accounts.where((account) {
                          final query = _searchQuery.toLowerCase();
                          final issuerMatch =
                              account.issuer?.toLowerCase().contains(query) ??
                              false;
                          final nameMatch = account.accountName
                              .toLowerCase()
                              .contains(query);
                          return issuerMatch || nameMatch;
                        }).toList();

                    if (filteredAccounts.isEmpty) {
                      // Check filtered list
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
                                    child: Text(
                                      'No accounts found matching your search.', // Updated empty state message
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      );
                    }
                    // Build the list view with Pull-to-Refresh inside a Card
                    return Card(
                      // Wrap with Card
                      elevation: 1,
                      color:
                          isDarkMode
                              ? AppColors
                                  .cCardDarkColor // Use custom dark color
                              : Theme.of(
                                context,
                              ).cardColor, // Use default theme color for light mode
                      margin: const EdgeInsets.only(
                        top: 8.0,
                        left: 16.0,
                        right: 16.0,
                        bottom: 16.0,
                      ), // Increased margin
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
                          itemCount:
                              filteredAccounts
                                  .length, // Use filtered list length
                          separatorBuilder:
                              (context, index) => const Divider(
                                height: 1, // Make divider thin
                                thickness: 1, // Explicit thickness
                                // Optional: Add indent or endIndent if needed
                                // indent: 16.0,
                                // endIndent: 16.0,
                              ),
                          itemBuilder: (context, index) {
                            final account =
                                filteredAccounts[index]; // Use filtered list item
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0,
                                ),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
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
                                  } else if (_currentCodes.containsKey(
                                    account.id,
                                  )) {
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Code copied to clipboard',
                                          ),
                                          duration: Duration(
                                            seconds: 1,
                                          ), // Shorter duration
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14.0,
                                        vertical: 10.0,
                                      ), // Padding for the row
                                      child: Row(
                                        children: [
                                          // 1. Logo (Cropped with rounded corners) - Updated
                                          SizedBox(
                                            // Constrain the size
                                            width: 40,
                                            height: 40,
                                            child: ClipRRect(
                                              // Apply rounded corners directly to the image
                                              borderRadius:
                                                  BorderRadius.circular(4.0),
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
                                                  account.issuer ??
                                                      'Unknown Issuer',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  account.accountName,
                                                  style:
                                                      Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8), // Spacing
                                          // 3. TOTP Code
                                          Text(
                                            displayCode,
                                            style: const TextStyle(
                                              fontSize:
                                                  22, // Slightly smaller code?
                                              fontWeight: FontWeight.bold,
                                              letterSpacing:
                                                  1.5, // Adjust spacing
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
                                                Colors
                                                    .grey, // Set progress color to green
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
                  return const Center(
                    child: Text('An unexpected state occurred.'),
                  );
                }, // End BlocConsumer builder
              ), // End BlocConsumer
            ), // End Expanded
          ], // End Column children
        ), // End Column
      ), // End GestureDetector
    ); // End Scaffold
  } // End build method
} // End _AccountsPageState class
