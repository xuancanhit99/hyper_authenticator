import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_auth_ui/supabase_auth_ui.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart'
    as app_auth;
// Import the common header widget
import 'package:hyper_authenticator/common/header_form.dart';

// No GoRouter needed here directly for navigation *within* auth,
// but keep it in scope if needed for other actions.

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen for specific Bloc states if needed for feedback (e.g., password reset)
    return BlocListener<app_auth.AuthBloc, app_auth.AuthState>(
      listener: (context, state) {
        if (state is app_auth.AuthFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('An error occurred: ${state.message}'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
        } else if (state is app_auth.AuthPasswordResetEmailSent) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: const Text(
                  'Password recovery email sent! Check your inbox.',
                ),
                backgroundColor: Colors.green,
              ),
            );
        }
      },
      child: Scaffold(
        // appBar: AppBar(title: const Text('Login')), // Optional: Add if needed
        body: SafeArea(
          // Ensure UI respects notches/status bars
          child: ListView(
            // Use ListView for scrolling on smaller screens
            padding: const EdgeInsets.all(24.0),
            children: [
              // --- Header ---
              const HeaderForm(
                image: 'assets/logo/mirea.png',
                title: 'Welcome Back!',
                subtitle: 'Sign in or create an account to get started.',
                // Center align the header content
                crossAxisAlignment: CrossAxisAlignment.center,
                textAlign: TextAlign.center,
                heightBetween: 20, // Keep existing spacing or adjust as needed
              ),
              const SizedBox(height: 32.0), // Spacing after header

              // Your App Logo or Title (Optional) - Removed redundant comment block

              // --- Supabase Auth UI Widget ---
              SupaEmailAuth(
                // Use Supabase.instance.client directly as intended by the library
                isInitiallySigningIn: true,

                // Or SupaAuthAction.signUp to start with Sign Up view

                // Redirect URL for password recovery link (MUST match Supabase config)
                // This is where Supabase redirects the user *after* they click the email link.
                // Use custom URL scheme or Universal Links/App Links.
                // Example using a custom scheme 'myapp':
                // passwordResetRedirectTo: 'myapp://reset-password', // Configure this scheme in AndroidManifest/Info.plist
                onSignInComplete: (AuthResponse response) {
                  // Called on successful sign-in.
                  // AuthBloc's stream listener and GoRouter redirect handle navigation.
                  debugPrint('Sign In successful: ${response.user?.email}');
                },
                onSignUpComplete: (AuthResponse response) {
                  // Called on successful sign-up.
                  // If email verification is required, user might not be 'authenticated' yet.
                  // AuthBloc stream + router redirect handles the app state change.
                  if (response.user?.emailConfirmedAt == null &&
                      Supabase.instance.client.auth.currentSession == null) {
                    debugPrint(
                      'Sign Up complete, email verification likely pending: ${response.user?.email}',
                    );
                    // Optionally show a message like "Please check your email to verify your account."
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Sign Up successful! Check your email for verification.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    debugPrint(
                      'Sign Up successful and verified/logged in: ${response.user?.email}',
                    );
                  }
                },
                onError: (error) {
                  debugPrint('SupaEmailAuth Error: $error');
                  // If you dispatch an event, use the prefix:
                  // context.read<app_auth.AuthBloc>().add(app_auth.AuthExternalErrorOccurred(error.toString()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error is AuthException
                            ? error.message
                            : 'An unexpected error occurred.',
                      ),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                },

                // --- Forgot Password Integration ---
                onPasswordResetEmailSent: () {
                  debugPrint(
                    'Password reset email request sent via SupaEmailAuth.',
                  );
                  // Use the BlocListener above to show feedback from AuthPasswordResetEmailSent state
                  // Or show direct feedback here:
                  // ScaffoldMessenger.of(context).showSnackBar(
                  //    const SnackBar(content: Text('Password recovery email sent! Check your inbox.'), backgroundColor: Colors.green),
                  // );
                },
                // This callback uses Supabase.instance.client.auth.resetPasswordForEmail internally
                // We don't need to manually call our Bloc/Repository for *this specific UI action*

                // --- Customization ---
                metadataFields: [
                  // Add extra fields for Sign Up if needed
                  // InputMetadata(label: 'Username', key: 'username'),
                ],
                // Add custom widgets above or below the form
                // BasaEmailAuth uses `Theme.of(context)` for styling. Ensure AppTheme provides good defaults.
                // Example: Add custom spacing or a logo
                // prependedWidgets: [
                //    const SizedBox(height: 50),
                //    // Your Logo Widget
                //    const SizedBox(height: 50),
                // ],
              ),
              const SizedBox(height: 20),
              // Optional: Add links for Terms of Service / Privacy Policy
              // Row(
              //    mainAxisAlignment: MainAxisAlignment.center,
              //    children: [
              //       TextButton(onPressed: () { /* Navigate */ }, child: Text('Terms')),
              //       Text(' | '),
              //       TextButton(onPressed: () { /* Navigate */ }, child: Text('Privacy')),
              //    ]
              // )
            ],
          ),
        ),
      ),
    );
  }
}
