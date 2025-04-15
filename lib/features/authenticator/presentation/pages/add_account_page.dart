import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';

class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key});

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _secretController = TextEditingController();

  bool _isScanning = false; // To toggle between manual entry and scanner view
  MobileScannerController scannerController =
      MobileScannerController(); // Controller for scanner

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    scannerController.dispose(); // Dispose scanner controller
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    // Stop scanning immediately after detection
    scannerController.stop();
    setState(() {
      _isScanning = false;
    }); // Switch back to form view

    final String? code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) {
      _showError('Could not read QR code data.');
      return;
    }

    debugPrint('QR Code Scanned: $code');
    try {
      final uri = Uri.parse(code);

      // Basic validation
      if (uri.scheme != 'otpauth' || uri.host != 'totp') {
        throw const FormatException(
          'Invalid QR code. Must start with otpauth://totp/',
        );
      }

      final secret = uri.queryParameters['secret'];
      final issuer = uri.queryParameters['issuer'];
      // Label is in the path segment, potentially with issuer prefix
      String label = '';
      if (uri.pathSegments.isNotEmpty) {
        label = Uri.decodeComponent(uri.pathSegments.last);
        if (issuer != null && label.startsWith('$issuer:')) {
          // Remove issuer prefix if present
          label = label.substring(issuer.length + 1).trim();
        }
      }

      if (secret == null || secret.isEmpty) {
        throw const FormatException('Missing secret key in QR code.');
      }

      // Parse optional OTP parameters with defaults
      final String algorithm =
          uri.queryParameters['algorithm']?.toUpperCase() ?? 'SHA1';
      final int digits =
          int.tryParse(uri.queryParameters['digits'] ?? '6') ?? 6;
      final int period =
          int.tryParse(uri.queryParameters['period'] ?? '30') ?? 30;

      // Basic validation for parameters (optional but recommended)
      if (!['SHA1', 'SHA256', 'SHA512'].contains(algorithm)) {
        _showError('Unsupported algorithm specified: $algorithm. Using SHA1.');
        // Fallback or throw error - choosing fallback for now
        // throw const FormatException('Unsupported algorithm specified in QR code.');
      }
      if (digits < 6 || digits > 8) {
        _showError('Unsupported digits specified: $digits. Using 6.');
        // Fallback or throw error
        // throw const FormatException('Unsupported number of digits specified in QR code.');
      }
      if (period <= 0) {
        _showError('Invalid period specified: $period. Using 30.');
        // Fallback or throw error
        // throw const FormatException('Invalid period specified in QR code.');
      }

      // Dispatch event to add account with all parameters
      context.read<AccountsBloc>().add(
        AddAccountRequested(
          issuer: issuer ?? '', // Use issuer from query or empty string
          accountName:
              label.isNotEmpty
                  ? label
                  : (issuer ??
                      'Unknown Account'), // Use parsed label or issuer or default
          secretKey: secret, // Pass the secret directly
          // Use validated/defaulted values
          algorithm:
              ['SHA1', 'SHA256', 'SHA512'].contains(algorithm)
                  ? algorithm
                  : 'SHA1',
          digits: (digits >= 6 && digits <= 8) ? digits : 6,
          period: (period > 0) ? period : 30,
        ),
      );

      // Navigation and feedback are now handled by BlocListener
    } on FormatException catch (e) {
      debugPrint('Error parsing OTP Auth URI: $e');
      _showError('Failed to parse QR code: ${e.message}');
    } catch (e) {
      debugPrint('Unexpected error handling QR code: $e');
      _showError('An unexpected error occurred while processing the QR code.');
    }
  }

  void _submitManualEntry() {
    if (_formKey.currentState!.validate()) {
      // Dispatch event with default OTP parameters for manual entry
      context.read<AccountsBloc>().add(
        AddAccountRequested(
          issuer: _issuerController.text.trim(),
          accountName: _accountNameController.text.trim(),
          secretKey: _secretController.text.trim(),
          // Use standard defaults for manual entry
          algorithm: 'SHA1',
          digits: 6,
          period: 30,
        ),
      );
      // Navigation and feedback are now handled by BlocListener
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
        backgroundColor:
            Theme.of(context).scaffoldBackgroundColor, // Set background color
        elevation: 0, // Remove shadow
        title: Text(_isScanning ? 'Scan QR Code' : 'Add Account'),
        actions: [
          // Toggle Button
          IconButton(
            icon: Icon(_isScanning ? Icons.edit : Icons.qr_code_scanner),
            tooltip: _isScanning ? 'Enter Manually' : 'Scan QR Code',
            onPressed: () {
              setState(() {
                _isScanning = !_isScanning;
                if (_isScanning) {
                  scannerController
                      .start(); // Start scanner when switching to scan view
                } else {
                  scannerController
                      .stop(); // Stop scanner when switching to manual view
                }
              });
            },
          ),
        ],
      ),
      body: BlocListener<AccountsBloc, AccountsState>(
        // Listen for state changes to handle navigation/feedback after add attempt
        listener: (context, state) {
          // We need to know the *previous* state to ensure we only pop
          // after a successful add operation finishes loading.
          // A simple check for AccountsLoaded might pop prematurely if the
          // BLoC was already in that state when the page was pushed.
          // However, the current BLoC reloads (Loading -> Loaded) after adding.
          // So, listening for AccountsLoaded should be sufficient here.

          if (state is AccountsLoaded) {
            // Check if the page is still mounted before interacting with context
            if (mounted) {
              // Check if we were previously in a state indicating an add was in progress
              // This logic might need refinement depending on exact state transitions.
              // For now, assume AccountsLoaded after AddAccountRequested implies success.
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account added successfully!')),
              );
            }
          } else if (state is AccountsError) {
            if (mounted) {
              // Check if the error is relevant to the add operation.
              // The current BLoC emits a generic AccountsError.
              // We might need a more specific error state later if needed.
              _showError('Failed to add account: ${state.message}');
              // Optionally restart scanner or allow retry for QR scan
              if (_isScanning && mounted) {
                // Add a small delay before restarting scanner to avoid immediate re-scan issues
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) scannerController.start();
                });
              }
            }
          }
          // Consider adding handling for AccountsLoading if needed, e.g., show a spinner overlay
        },
        child: _isScanning ? _buildScannerView() : _buildManualEntryForm(),
      ),
    );
  }

  Widget _buildScannerView() {
    return MobileScanner(
      controller: scannerController, // Use the controller
      onDetect: _handleBarcode,
    );
  }

  Widget _buildManualEntryForm() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          // Use ListView for scrollability on small screens
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
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the secret key';
                }
                // Optional: Add a more robust Base32 validation if needed
                return null;
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _submitManualEntry,
              child: const Text('Add Account'),
            ),
          ],
        ),
      ),
    );
  }
}
