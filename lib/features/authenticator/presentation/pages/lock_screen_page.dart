import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
// Imports no longer needed after removing listener
// import 'package:go_router/go_router.dart';
// import 'package:hyper_authenticator/core/router/app_router.dart';

class LockScreenPage extends StatefulWidget {
  const LockScreenPage({super.key});

  @override
  State<LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends State<LockScreenPage> {
  bool _authTriggered = false; // Flag to prevent multiple triggers

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure context is available and bloc is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAuthenticationIfNeeded();
    });
  }

  void _triggerAuthenticationIfNeeded() {
    // Check if mounted before accessing context after async gap
    if (!mounted) return;

    final localAuthBloc = context.read<LocalAuthBloc>();
    // Trigger auth automatically only if required and not already triggered
    if (localAuthBloc.state is LocalAuthRequired && !_authTriggered) {
      setState(() {
        _authTriggered = true; // Mark as triggered
      });
      print(
        "[LockScreenPage] State is LocalAuthRequired, triggering Authenticate event automatically.",
      );
      localAuthBloc.add(Authenticate());
    } else {
      print(
        "[LockScreenPage] Initial state is ${localAuthBloc.state}, not triggering auto-auth.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Optional: Use BlocListener if you need to react to state changes *after* initial build
    // For example, if auth fails and returns to LocalAuthRequired, you might want to re-trigger
    // or show a message. For now, initState handles the initial trigger.

    return Scaffold(
      // Optionally add an AppBar
      // appBar: AppBar(title: const Text('App Locked')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Replace Icon with Image.asset
            Image.asset(
              'assets/logos/hyper-logo-green-non-bg.png', // Assuming this is the correct path
              height: 80, // Set height similar to the original icon size
              // Optional: Add width, fit, errorBuilder etc. if needed
              // width: 80,
              // fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback if logo fails to load
                return const Icon(
                  Icons.lock_outline,
                  size: 80,
                  color: Colors.grey,
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'App Locked',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('Please authenticate to continue.'),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.fingerprint), // Or appropriate icon
              label: const Text('Unlock App'),
              onPressed: () {
                // Manually trigger authentication attempt if button is pressed
                print(
                  "[LockScreenPage] Manual Unlock button pressed. Triggering Authenticate.",
                );
                context.read<LocalAuthBloc>().add(Authenticate());
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
            ),
            // Display error messages from the bloc if any
            BlocBuilder<LocalAuthBloc, LocalAuthState>(
              builder: (context, state) {
                if (state is LocalAuthError) {
                  // Reset the trigger flag if an error occurs, allowing retry
                  // Note: This might cause immediate re-trigger if error state persists.
                  // Consider more sophisticated retry logic if needed.
                  // WidgetsBinding.instance.addPostFrameCallback((_) {
                  //   if (mounted) {
                  //     setState(() { _authTriggered = false; });
                  //   }
                  // });
                  return Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text(
                      'Error: ${state.message}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const SizedBox.shrink(); // No error
              },
            ),
          ],
        ),
      ), // Close Center
    ); // Close Scaffold and return statement
  }
}
