import 'dart:async';
// For FontFeature

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // Import Slidable
import 'package:provider/provider.dart'; // Import Provider
import 'package:hyper_authenticator/core/theme/theme_provider.dart'; // Import ThemeProvider
import 'package:qr_flutter/qr_flutter.dart'; // Import QR Flutter
import 'package:hyper_authenticator/core/constants/app_colors.dart'; // Import AppColors (needed for Card)
// For NoParams
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/generate_totp_code.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart'; // Import Countdown Timer
import 'package:hyper_authenticator/injection_container.dart';
import 'package:go_router/go_router.dart'; // Import GoRouter for navigation
import 'package:hyper_authenticator/core/router/app_router.dart'; // Import AppRoutes
// Import EditAccountPage

// TODO: Define route for AddAccountPage
// import 'add_account_page.dart'; // Will create this later
// TODO: Define route for EditAccountPage
// import 'edit_account_page.dart'; // Will create this later

class AccountsPage extends StatefulWidget {
  const AccountsPage({
    super.key,
    this.now = DateTime.now,
    this.generateTotpCode,
  });

  final DateTime Function() now;
  final GenerateTotpCode? generateTotpCode;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  late int _epochSeconds;
  // Store current codes to avoid recalculating every build
  final Map<String, String> _currentCodes = {};
  final Map<String, _TotpCodeCacheEntry> _codeCache = {};
  // Inject GenerateTotpCode use case
  late final GenerateTotpCode _generateTotpCode;
  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generateTotpCode = widget.generateTotpCode ?? sl<GenerateTotpCode>();
    _epochSeconds = _readEpochSeconds();
    _searchController.addListener(
      _onSearchChanged,
    ); // Add listener for search input
    context.read<AccountsBloc>().add(LoadAccounts());
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _searchController.removeListener(_onSearchChanged); // Remove listener
    _searchController.dispose(); // Dispose controller
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    final now = widget.now();
    final millisecondsUntilNextSecond =
        1000 - (now.millisecondsSinceEpoch % 1000);
    _timer = Timer(Duration(milliseconds: millisecondsUntilNextSecond), () {
      _refreshClock();
      if (!mounted) return;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _refreshClock();
      });
    });
  }

  int _readEpochSeconds() => widget.now().millisecondsSinceEpoch ~/ 1000;

  void _refreshClock({bool force = false}) {
    if (!mounted) return;
    final nextEpochSeconds = _readEpochSeconds();
    if (!force && nextEpochSeconds == _epochSeconds) return;
    setState(() {
      _epochSeconds = nextEpochSeconds;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshClock(force: true);
      _startTimer();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
    }
  }

  // Listener for search query changes
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  Future<String> _getCodeForAccount(
    AuthenticatorAccount account,
    TotpTimeWindow timeWindow,
  ) {
    final cached = _codeCache[account.id];
    if (cached != null &&
        cached.account == account &&
        cached.timeStep == timeWindow.timeStep) {
      return cached.future;
    }

    _currentCodes.remove(account.id);
    final future = _generateCodeForAccount(account, timeWindow);
    _codeCache[account.id] = _TotpCodeCacheEntry(
      account: account,
      timeStep: timeWindow.timeStep,
      future: future,
    );
    return future;
  }

  Future<String> _generateCodeForAccount(
    AuthenticatorAccount account,
    TotpTimeWindow timeWindow,
  ) async {
    // Pass all necessary parameters from the account to the use case
    final result = await _generateTotpCode(
      GenerateTotpCodeParams(
        secretKey: account.secretKey,
        algorithm: account.algorithm,
        digits: account.digits,
        period: account.period,
        timestampMilliseconds:
            timeWindow.timeStep *
            account.period *
            Duration.millisecondsPerSecond,
      ),
    );
    return result.fold(
      (failure) => 'Lỗi', // Handle error display
      (code) => code,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor, // Set background color
        elevation: 0, // Remove shadow for a flatter look if desired
        title: const Text('Mã xác thực'),
        actions: [
          // Theme switcher icon
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
                  iconData = Icons.brightness_auto_outlined;
                  break;
              }
              return PopupMenuButton<ThemeMode>(
                icon: Icon(
                  iconData,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                tooltip: 'Đổi giao diện',
                onSelected: (ThemeMode result) {
                  // Use ThemeProvider to set the theme
                  Provider.of<ThemeProvider>(
                    context,
                    listen: false,
                  ).setThemeMode(result);
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<ThemeMode>>[
                      const PopupMenuItem<ThemeMode>(
                        value: ThemeMode.system,
                        child: ListTile(
                          leading: Icon(Icons.brightness_auto_outlined),
                          title: Text('Theo hệ thống'),
                        ),
                      ),
                      const PopupMenuItem<ThemeMode>(
                        value: ThemeMode.light,
                        child: ListTile(
                          leading: Icon(Icons.light_mode_outlined),
                          title: Text('Sáng'),
                        ),
                      ),
                      const PopupMenuItem<ThemeMode>(
                        value: ThemeMode.dark,
                        child: ListTile(
                          leading: Icon(Icons.dark_mode_outlined),
                          title: Text('Tối'),
                        ),
                      ),
                    ],
              );
            },
          ),
          // Apply background color directly to IconButton using style
          Padding(
            // Add padding to prevent button touching edge
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.add, size: 20), // Reduced icon size
              color: isDarkMode
                  ? Colors
                        .white // Light icon on dark background
                  : Colors.black87, // Darker icon on light background
              tooltip: 'Thêm tài khoản',
              style: IconButton.styleFrom(
                backgroundColor: isDarkMode
                    ? AppColors
                          .cDarkIconBg // Dark background for dark mode
                    : AppColors.cLightIconBg, // Light background for light mode
                shape:
                    const CircleBorder(), // Slightly reduced padding for smaller icon
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
                  hintText: 'Tìm dịch vụ hoặc ứng dụng...',
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
                  fillColor: isDarkMode
                      ? AppColors
                            .cCardDarkColor // Use custom dark color
                      : null, // Use default theme fill color for light mode (or specify one)
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ), // Adjust padding
                  suffixIcon: _searchQuery.isNotEmpty
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
                  if (state is AccountsLoaded) {
                    final accountIds = state.accounts
                        .map((account) => account.id)
                        .toSet();
                    _codeCache.removeWhere(
                      (accountId, _) => !accountIds.contains(accountId),
                    );
                    _currentCodes.removeWhere(
                      (accountId, _) => !accountIds.contains(accountId),
                    );
                  }
                  if (state is AccountsError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi: ${state.message}')),
                    );
                  }
                  // Optional: Show success messages for add/delete if specific states were used
                },
                builder: (context, state) {
                  if (state is AccountsLoading || state is AccountsInitial) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is AccountsLoaded) {
                    // Filter accounts based on search query
                    final List<AuthenticatorAccount> filteredAccounts = state
                        .accounts
                        .where((account) {
                          final query = _searchQuery.toLowerCase();
                          final issuerMatch = account.issuer
                              .toLowerCase()
                              .contains(query);
                          final nameMatch = account.accountName
                              .toLowerCase()
                              .contains(query);
                          return issuerMatch || nameMatch;
                        })
                        .toList();

                    if (filteredAccounts.isEmpty) {
                      // Check filtered list
                      // Wrap empty state message with RefreshIndicator as well
                      return RefreshIndicator(
                        onRefresh: () async {
                          context.read<AccountsBloc>().add(LoadAccounts());
                        },
                        child: LayoutBuilder(
                          // Use LayoutBuilder to allow scrolling for refresh
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Không tìm thấy tài khoản phù hợp.',
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
                      color: isDarkMode
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
                          itemCount: filteredAccounts
                              .length, // Use filtered list length
                          separatorBuilder: (context, index) => const Divider(
                            height: 1, // Make divider thin
                            thickness: 1, // Explicit thickness
                            // Optional: Add indent or endIndent if needed
                            // indent: 16.0,
                            // endIndent: 16.0,
                          ),
                          itemBuilder: (context, index) {
                            final account =
                                filteredAccounts[index]; // Use filtered list item
                            final timeWindow = TotpTimeWindow.fromEpochSeconds(
                              epochSeconds: _epochSeconds,
                              periodSeconds: account.period,
                            );
                            // --- Start Slidable Widget ---
                            return Slidable(
                              key: Key(account.id),
                              groupTag:
                                  '0', // For SlidableStrechAction animation
                              endActionPane: ActionPane(
                                motion:
                                    const StretchMotion(), // Changed to StretchMotion for desired effect
                                extentRatio:
                                    0.6, // Show 1/2 of the slidable actions
                                children: [
                                  SlidableAction(
                                    onPressed: (_) =>
                                        _showQrCodeDialog(context, account),
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    icon: Icons.qr_code,
                                    // label: 'QR Code',
                                  ),
                                  SlidableAction(
                                    onPressed: (_) {
                                      context.push(
                                        AppRoutes.editAccount,
                                        extra: account,
                                      );
                                    },
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    icon: Icons.edit,
                                    // label: 'Edit',
                                  ),
                                  SlidableAction(
                                    onPressed: (_) =>
                                        _showDeleteConfirmationDialog(
                                          context,
                                          account,
                                        ),
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    icon: Icons.delete,
                                    // label: 'Delete',
                                  ),
                                ],
                              ),
                              child: FutureBuilder<String>(
                                // Use future builder to get the code asynchronously
                                future: _getCodeForAccount(account, timeWindow),
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
                                        horizontal: 8.0,
                                        vertical: 10.0,
                                      ), // Padding for the row
                                      child: Row(
                                        children: [
                                          // 1. Logo (Cropped with rounded corners) - Updated
                                          AccountAvatar(issuer: account.issuer),
                                          const SizedBox(width: 12), // Spacing
                                          // 2. Issuer / Account Name
                                          Expanded(
                                            // Takes available space
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  account.issuer,
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
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8), // Spacing
                                          // 3. TOTP Code và 4. Countdown Timer trong hàng ngang với căn giữa theo trục dọc
                                          Text(
                                            displayCode,
                                            style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.3,
                                              fontFeatures: [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8), // Spacing
                                          CircularCountdownTimer(
                                            secondsRemaining:
                                                timeWindow.secondsRemaining,
                                            periodSeconds: account.period,
                                            size: 18,
                                            backgroundColor: Colors.transparent,
                                            progressColor: Colors.grey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  // --- End New Row Layout ---
                                }, // End FutureBuilder builder
                              ), // End FutureBuilder
                            ); // --- End Slidable Widget ---
                          }, // End itemBuilder
                        ), // End ListView.separated
                      ), // End RefreshIndicator
                    ); // End Card
                  } // End of `if (state is AccountsLoaded)`
                  // Should not happen if states are handled, but provide fallback
                  return const Center(
                    child: Text('Ứng dụng gặp trạng thái không mong đợi.'),
                  );
                }, // End BlocConsumer builder
              ), // End BlocConsumer
            ), // End Expanded
          ], // End Column children
        ), // End Column
      ), // End GestureDetector
    ); // End Scaffold
  } // End build method

  // --- Helper method to show QR Code Dialog ---
  void _showQrCodeDialog(BuildContext context, AuthenticatorAccount account) {
    // Construct the OTPAuth URI (Standard format for 2FA export)
    // otpauth://TYPE/LABEL?PARAMETERS
    // TYPE: totp or hotp
    // LABEL: issuer:accountName or issuer (accountName)
    // PARAMETERS: secret, issuer, algorithm, digits, period
    const type = 'totp'; // Assuming all accounts are TOTP for now
    final label = Uri.encodeComponent(
      '${account.issuer}:${account.accountName}',
    );
    final secret = account.secretKey;
    final issuer = Uri.encodeComponent(account.issuer);
    final algorithm = account.algorithm.toUpperCase();
    final digits = account.digits;
    final period = account.period;

    final qrData =
        'otpauth://$type/$label?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$digits&period=$period';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Mã QR của tài khoản'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Nhà cung cấp: ${account.issuer}'),
                Text('Tài khoản: ${account.accountName}'),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    // Add a white background container
                    color: Colors.white,
                    padding: const EdgeInsets.all(8.0), // Add padding around QR
                    child: SizedBox(
                      width: 200.0,
                      height: 200.0,
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size:
                            200.0, // This size is for the QR code itself within the QrImageView
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Optional: Display raw QR data for debugging or manual entry
                // SelectableText(
                //   'Raw Data: $qrData',
                //   style: TextStyle(fontSize: 10, color: Colors.grey),
                // ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Đóng'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // --- Helper method to show Delete Confirmation Dialog ---
  void _showDeleteConfirmationDialog(
    BuildContext context,
    AuthenticatorAccount account,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AccountAvatar(issuer: account.issuer, size: 60),
              const SizedBox(height: 16),
              Text(
                'Bạn có chắc muốn xóa tài khoản này?',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Nhà cung cấp: ${account.issuer}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Tài khoản: ${account.accountName}'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Hủy'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Xóa'),
              onPressed: () {
                context.read<AccountsBloc>().add(
                  DeleteAccountRequested(accountId: account.id),
                );
                Navigator.of(dialogContext).pop(); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Đã xóa ${account.issuer} (${account.accountName})',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
} // End _AccountsPageState class

class _TotpCodeCacheEntry {
  const _TotpCodeCacheEntry({
    required this.account,
    required this.timeStep,
    required this.future,
  });

  final AuthenticatorAccount account;
  final int timeStep;
  final Future<String> future;
}
