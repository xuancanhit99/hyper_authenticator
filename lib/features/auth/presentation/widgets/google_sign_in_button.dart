import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthState>(
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: state is AuthLoading
              ? null
              : () => context.read<AuthBloc>().add(AuthGoogleSignInRequested()),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logos/authenticators/google.png',
                width: 20,
                height: 20,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('Tiếp tục với Google', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
        if (state is AuthGoogleRedirectStarted)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Hoàn tất đăng nhập trong trình duyệt. Bạn có thể thử lại nếu đã đóng cửa sổ.',
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider()),
            Flexible(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('hoặc dùng email', textAlign: TextAlign.center),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}
