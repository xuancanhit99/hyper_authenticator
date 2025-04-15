import 'package:flutter/material.dart';

class AuthHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const AuthHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo
        Image.asset(
          'assets/logo/hyper-logo-green-non-bg-alt.png', // Ensure this path is correct
          height: 80, // Adjust height as needed
          errorBuilder: (context, error, stackTrace) {
            // Fallback if image fails to load
            return const Icon(Icons.shield_outlined, size: 80);
          },
        ),
        const SizedBox(height: 24),
        // Title
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        // Subtitle (Optional)
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32), // Spacing before the form fields
      ],
    );
  }
}
