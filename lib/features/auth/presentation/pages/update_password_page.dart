import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart'; // Assuming router paths are defined here
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/widgets/auth_header.dart';

class UpdatePasswordPage extends StatefulWidget {
  // Optionally receive the access token from the deep link if needed,
  // though Supabase client often handles session automatically.
  // final String? accessToken;

  const UpdatePasswordPage({
    super.key,
    // this.accessToken,
  });

  @override
  State<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends State<UpdatePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  // bool _isLoading = false; // Replaced by Bloc state
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updatePassword(BuildContext context) {
    // Pass context
    if (_formKey.currentState!.validate()) {
      // Dispatch event to Bloc
      context.read<AuthBloc>().add(
        AuthPasswordUpdateRequested(newPassword: _passwordController.text),
      );
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a new password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your new password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with BlocListener
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message)));
        }
        // Assuming successful update might trigger AuthAuthenticated or a specific success state
        // For now, let's show a message and navigate on success (can be refined)
        // We might need a dedicated AuthPasswordUpdateSuccess state for clarity
        if (state is AuthAuthenticated) {
          // Or a specific success state
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Password updated successfully! Please log in.'),
              ),
            );
          context.go(AppRoutes.login); // Navigate to login after success
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set New Password'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          // Automatically adds back button if navigable
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AuthHeader(
                      title: 'Set New Password',
                      subtitle: 'Enter and confirm your new password',
                    ),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'New Password*',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: _validatePassword,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password*',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureConfirmPassword,
                      validator: _validateConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted:
                          (_) => _updatePassword(context), // Pass context
                    ),
                    const SizedBox(height: 24),
                    // Use BlocBuilder for loading state
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return ElevatedButton(
                          onPressed:
                              isLoading
                                  ? null
                                  : () =>
                                      _updatePassword(context), // Pass context
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: Theme.of(context).textTheme.titleMedium,
                          ),
                          child:
                              isLoading
                                  ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Text('Update Password'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ), // End Scaffold
    ); // End BlocListener
  }
}
