import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';

class LockScreenPage extends StatelessWidget {
  const LockScreenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Optionally add an AppBar
      // appBar: AppBar(title: const Text('App Locked')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
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
                // Trigger authentication attempt
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
      ),
    );
  }
}
