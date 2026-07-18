import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

  bool _isScanning = false;
  final MobileScannerController scannerController = MobileScannerController(
    autoStart: false,
  );

  @override
  void initState() {
    super.initState();
    _issuerController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    scannerController.dispose(); // Dispose scanner controller
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    scannerController.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
    });

    final String? code = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) {
      _showError('Không thể đọc dữ liệu trong mã QR.');
      return;
    }

    try {
      final account = TotpUriParser.parse(code);
      context.read<AccountsBloc>().add(
        AddAccountRequested(
          issuer: account.issuer,
          accountName: account.accountName,
          secretKey: account.secretKey,
          algorithm: account.algorithm,
          digits: account.digits,
          period: account.period,
        ),
      );
      _issuerController.text = account.issuer;
      _accountNameController.text = account.accountName;
      _secretController.text = account.secretKey;
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Đã xảy ra lỗi khi xử lý mã QR.');
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

  // --- Function to pick image and analyze QR code ---
  Future<void> _pickAndAnalyzeImage() async {
    final ImagePicker picker = ImagePicker();
    // Pick an image
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) {
      return;
    }

    try {
      final BarcodeCapture? barcodeCapture = await scannerController
          .analyzeImage(image.path);

      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        _handleBarcode(barcodeCapture);
      } else {
        _showError('Không tìm thấy mã QR trong ảnh đã chọn.');
      }
    } catch (_) {
      _showError('Không thể phân tích ảnh đã chọn.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor, // Set background color
        elevation: 0, // Remove shadow
        title: Text(_isScanning ? 'Scan QR Code' : 'Add Account'),
        actions: [
          if (!_isScanning && PlatformCapabilities.supportsBarcodeImageAnalysis)
            IconButton(
              icon: const Icon(Icons.image_outlined),
              tooltip: 'Chọn ảnh mã QR',
              onPressed: _pickAndAnalyzeImage,
            ),
          if (PlatformCapabilities.supportsBarcodeScanning)
            IconButton(
              icon: Icon(_isScanning ? Icons.edit : Icons.qr_code_scanner),
              tooltip: _isScanning ? 'Nhập thủ công' : 'Quét mã QR',
              onPressed: () {
                final shouldScan = !_isScanning;
                setState(() {
                  _isScanning = shouldScan;
                });
                if (shouldScan) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      scannerController.start();
                    }
                  });
                } else {
                  scannerController.stop();
                }
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: AccountAvatar(issuer: _issuerController.text, size: 72),
              ),
            ),
            TextFormField(
              controller: _issuerController,
              decoration: const InputDecoration(
                labelText: 'Nhà cung cấp (ví dụ: Google, GitHub)',
                hintText: 'Nhập tên nhà cung cấp',
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Please enter an issuer'
                  : null,
              // Listener is in initState to update preview dynamically
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountNameController,
              decoration: const InputDecoration(
                labelText: 'Account Name (e.g., user@example.com)',
              ),
              validator: (value) => (value == null || value.isEmpty)
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
