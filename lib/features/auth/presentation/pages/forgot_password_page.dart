import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart'; // Assuming router paths are defined here
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/widgets/auth_header.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  // bool _isLoading = false; // Replaced by Bloc state

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _sendResetLink(BuildContext context) {
    // Pass context
    if (_formKey.currentState!.validate()) {
      // Dispatch event to Bloc
      context.read<AuthBloc>().add(
        AuthRecoverPasswordRequested(_emailController.text.trim()),
      );
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập email.';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Vui lòng nhập địa chỉ email hợp lệ.';
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
        if (state is AuthPasswordResetEmailSent) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Nếu tài khoản tồn tại, liên kết đặt lại mật khẩu đã được gửi. Hãy kiểm tra email.',
                ),
              ),
            );
          // Optionally pop after a delay or let user press back
          // Future.delayed(const Duration(seconds: 2), () {
          //   if (context.canPop()) context.pop();
          // });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Quên mật khẩu'),
          elevation: 0,
          backgroundColor: Colors.transparent,
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
                      title: 'Đặt lại mật khẩu',
                      subtitle: 'Nhập email để nhận liên kết đặt lại mật khẩu',
                    ),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) =>
                          _sendResetLink(context), // Pass context
                    ),
                    const SizedBox(height: 24),
                    // Use BlocBuilder for loading state
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () => _sendResetLink(context), // Pass context
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: Theme.of(context).textTheme.titleMedium,
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Gửi liên kết đặt lại'),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // Navigate back to Login page
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.login); // Fallback if cannot pop
                          // print('Navigate to Login (Fallback)');
                        }
                      },
                      child: const Text('Quay lại đăng nhập'),
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
