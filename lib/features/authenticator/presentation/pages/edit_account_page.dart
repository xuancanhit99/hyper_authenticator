import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';

class EditAccountPage extends StatefulWidget {
  final AuthenticatorAccount account;

  const EditAccountPage({super.key, required this.account});

  @override
  State<EditAccountPage> createState() => _EditAccountPageState();
}

class _EditAccountPageState extends State<EditAccountPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _issuerController;
  late TextEditingController _accountNameController;
  late TextEditingController _secretController;
  // OTP Parameters - For simplicity, we'll make them editable too,
  // though secret key is usually not changed after creation.
  // Advanced options might be hidden or read-only depending on UX.
  late TextEditingController _algorithmController;
  late TextEditingController _digitsController;
  late TextEditingController _periodController;

  @override
  void initState() {
    super.initState();
    _issuerController = TextEditingController(text: widget.account.issuer);
    _accountNameController = TextEditingController(
      text: widget.account.accountName,
    );
    _secretController = TextEditingController(text: widget.account.secretKey);
    _algorithmController = TextEditingController(
      text: widget.account.algorithm,
    );
    _digitsController = TextEditingController(
      text: widget.account.digits.toString(),
    );
    _periodController = TextEditingController(
      text: widget.account.period.toString(),
    );
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    _algorithmController.dispose();
    _digitsController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  void _submitUpdate() {
    if (_formKey.currentState!.validate()) {
      final updatedAccount = AuthenticatorAccount(
        id: widget.account.id, // Keep the original ID
        issuer: _issuerController.text.trim(),
        accountName: _accountNameController.text.trim(),
        secretKey:
            _secretController.text
                .trim(), // Secret key modification might be risky/complex in real 2FA
        algorithm: _algorithmController.text.trim().toUpperCase(),
        digits:
            int.tryParse(_digitsController.text.trim()) ??
            widget.account.digits,
        period:
            int.tryParse(_periodController.text.trim()) ??
            widget.account.period,
      );

      context.read<AccountsBloc>().add(
        UpdateAccountRequested(account: updatedAccount),
      );

      // Navigation and feedback will be handled by BlocListener
      // No longer needed:
      // Navigator.pop(context);
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Update logic not fully implemented in BLoC yet.')),
      // );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: const Text('Edit Account'),
      ),
      body: BlocListener<AccountsBloc, AccountsState>(
        listener: (context, state) {
          // Listen for AccountsLoaded, assuming BLoC reloads accounts after update
          if (state is AccountsLoaded) {
            // To prevent popping if EditAccountPage is pushed and BLoC is already in AccountsLoaded
            // We need a more specific state like AccountUpdateSuccess or a flag.
            // For now, this might pop immediately if not careful with BLoC state flow.
            // A simple way is to check if the *current* state of the BLoC has just transitioned
            // to AccountsLoaded AFTER an update operation.
            // However, the BLoC now reloads by adding LoadAccounts(), so this listener
            // should work similarly to AddAccountPage.
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              // Check if page is current
              // Check if the previous state was indicating an update was in progress or successful
              // This logic might need refinement. For simplicity, pop if loaded.
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account updated successfully!')),
              );
            }
          } else if (state is AccountsError) {
            if (mounted) {
              _showError('Failed to update account: ${state.message}');
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _issuerController,
                  decoration: const InputDecoration(
                    labelText: 'Issuer (e.g., Google, GitHub)',
                  ),
                  validator:
                      (value) =>
                          (value == null || value.isEmpty)
                              ? 'Please enter an issuer'
                              : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _accountNameController,
                  decoration: const InputDecoration(
                    labelText: 'Account Name (e.g., user@example.com)',
                  ),
                  validator:
                      (value) =>
                          (value == null || value.isEmpty)
                              ? 'Please enter an account name'
                              : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _secretController,
                  decoration: const InputDecoration(
                    labelText: 'Secret Key (Base32 encoded)',
                    // Consider making this read-only or adding strong warnings
                    // helperText: 'Warning: Changing the secret key will invalidate existing 2FA setups.',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the secret key';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  "Advanced Options (Edit with caution):",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _algorithmController,
                  decoration: const InputDecoration(
                    labelText: 'Algorithm (SHA1, SHA256, SHA512)',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please enter an algorithm';
                    if (![
                      'SHA1',
                      'SHA256',
                      'SHA512',
                    ].contains(value.toUpperCase())) {
                      return 'Invalid algorithm. Use SHA1, SHA256, or SHA512.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _digitsController,
                  decoration: const InputDecoration(
                    labelText: 'Digits (e.g., 6 or 8)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please enter number of digits';
                    final n = int.tryParse(value);
                    if (n == null) return 'Invalid number';
                    if (n < 6 || n > 8) return 'Digits must be 6, 7, or 8';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _periodController,
                  decoration: const InputDecoration(
                    labelText: 'Period (seconds, e.g., 30)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please enter period';
                    final n = int.tryParse(value);
                    if (n == null || n <= 0)
                      return 'Period must be a positive number';
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submitUpdate,
                  child: const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
