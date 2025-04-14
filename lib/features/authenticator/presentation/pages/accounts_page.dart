import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart'; // For NoParams
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/generate_totp_code.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
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

  @override
  void initState() {
    super.initState();
    // Load accounts when the page initializes
    context.read<AccountsBloc>().add(LoadAccounts());
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
            // Build the list view with Pull-to-Refresh
            return RefreshIndicator(
              // Start RefreshIndicator
              onRefresh: () async {
                // Dispatch LoadAccounts event when pulled
                context.read<AccountsBloc>().add(LoadAccounts());
              },
              child: ListView.builder(
                // Start ListView.builder (child of RefreshIndicator)
                itemCount: state.accounts.length,
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
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasData) {
                          displayCode = snapshot.data!;
                          // Format code with space
                          if (displayCode.length == 6) {
                            displayCode =
                                '${displayCode.substring(0, 3)} ${displayCode.substring(3)}';
                          }
                          _currentCodes[account.id] = displayCode; // Cache code
                        } else if (_currentCodes.containsKey(account.id)) {
                          displayCode =
                              _currentCodes[account
                                  .id]!; // Use cached code during refresh
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            // Simple countdown indicator
                            radius: 15,
                            child: Text(
                              '$_secondsRemaining',
                              style: const TextStyle(fontSize: 12),
                            ),
                            // TODO: Replace with a proper CircularProgressIndicator based on _secondsRemaining/30
                          ),
                          title: Text(account.issuer),
                          subtitle: Text(account.accountName),
                          trailing: Text(
                            displayCode,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: displayCode.replaceAll(' ', ''),
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code copied to clipboard'),
                              ),
                            );
                          },
                        );
                      }, // End FutureBuilder builder
                    ), // End FutureBuilder
                  ); // End Dismissible
                }, // End itemBuilder
              ), // End ListView.builder
            ); // End RefreshIndicator
          } // End of `if (state is AccountsLoaded)`
          // Should not happen if states are handled, but provide fallback
          return const Center(child: Text('An unexpected state occurred.'));
        }, // End BlocConsumer builder
      ), // End BlocConsumer
    ); // End Scaffold
  } // End build method
} // End _AccountsPageState class
