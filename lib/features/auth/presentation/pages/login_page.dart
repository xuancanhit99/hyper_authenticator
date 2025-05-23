import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart'; // Assuming router paths are defined here
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/widgets/auth_header.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // bool _isLoading = false; // Replaced by Bloc state
  bool _obscurePassword = true;
  bool _rememberMe = false; // State for Remember Me checkbox

  @override
  void initState() {
    super.initState();
    // Dispatch event to load remembered user when the page initializes
    context.read<AuthBloc>().add(LoadRememberedUser());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login(BuildContext context) {
    // Pass context for Bloc access
    if (_formKey.currentState!.validate()) {
      // Dispatch event to Bloc
      context.read<AuthBloc>().add(
        AuthSignInRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          rememberMe: _rememberMe, // Pass rememberMe value
        ),
      );
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    // Basic email validation regex
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with BlocListener to show errors
    return BlocListener<AuthBloc, AuthState>(
      // Listen for AuthInitial state to pre-fill email
      listenWhen:
          (previous, current) =>
              current is AuthInitial || current is AuthFailure,
      listener: (context, state) {
        if (state is AuthInitial) {
          // Pre-fill email if available
          if (state.rememberedEmail != null) {
            _emailController.text = state.rememberedEmail!;
          }
          // Set remember me checkbox state if available
          if (state.rememberedMeState != null) {
            setState(() {
              _rememberMe = state.rememberedMeState!;
            });
          }
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message)));
        }
        // Navigation on AuthAuthenticated is usually handled by a higher-level listener (e.g., in AppRouter or main App widget)
      },
      child: Scaffold(
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
                      title: 'Welcome Back!',
                      subtitle: 'Sign in to continue',
                    ),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        // Add suffix icon for password visibility toggle
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
                      obscureText: _obscurePassword, // Use state variable
                      validator: _validatePassword,
                      textInputAction: TextInputAction.done,
                      // Pass context to _login
                      onFieldSubmitted: (_) => _login(context),
                    ),
                    const SizedBox(height: 16),
                    // --- Remember Me & Forgot Password Row ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Remember Me part
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 24.0, // Constrain height
                              width: 24.0, // Constrain width
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (newValue) {
                                  setState(() {
                                    _rememberMe = newValue ?? false;
                                  });
                                },
                                visualDensity:
                                    VisualDensity
                                        .compact, // Make checkbox smaller
                                materialTapTargetSize:
                                    MaterialTapTargetSize
                                        .shrinkWrap, // Reduce tap area
                              ),
                            ),
                            const SizedBox(
                              width: 4,
                            ), // Small space between checkbox and text
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _rememberMe = !_rememberMe;
                                });
                              },
                              child: const Text("Remember Me"),
                            ),
                          ],
                        ),
                        // Forgot Password part
                        TextButton(
                          onPressed: () {
                            context.push(AppRoutes.forgotPassword);
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero, // Remove default padding
                            minimumSize:
                                Size.zero, // Remove minimum size constraint
                            tapTargetSize:
                                MaterialTapTargetSize
                                    .shrinkWrap, // Reduce tap area
                          ),
                          child: const Text('Forgot Password?'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Use BlocBuilder to handle loading state
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return ElevatedButton(
                          // Keep onPressed active, let Bloc handle loading state internally
                          onPressed: () => _login(context), // Pass context
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: Theme.of(context).textTheme.titleMedium,
                          ),
                          child:
                              isLoading
                                  ? SizedBox(
                                    // Remove const here
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      // Set indicator color based on theme brightness
                                      color:
                                          Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors
                                                  .black // Black indicator in dark mode
                                              : Colors
                                                  .white, // White indicator in light mode
                                    ),
                                  )
                                  : const Text('Login'),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account?"),
                        TextButton(
                          onPressed: () {
                            // Navigate to Register page
                            context.push(AppRoutes.register);
                            // print('Navigate to Register'); // Keep for debugging if needed
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero, // Remove default padding
                            // minimumSize:
                            // Size.zero, // Remove minimum size constraint
                            tapTargetSize:
                                MaterialTapTargetSize
                                    .shrinkWrap, // Reduce tap area
                          ),
                          child: const Text('Sign Up'),
                        ),
                      ],
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
