import 'package:flutter/material.dart';
import 'dart:io'; // Needed for File path

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/utils/logo_service.dart'; // Import LogoService
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/logo_picker_dialog.dart'; // Import LogoPickerDialog

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

  String? _selectedIssuer;
  List<String> _availableIssuers = [];
  String? _previewLogoPath;

  bool _isScanning = false; // To toggle between manual entry and scanner view
  MobileScannerController scannerController =
      MobileScannerController(); // Controller for scanner

  @override
  void initState() {
    super.initState();
    _loadAvailableIssuers();
    _issuerController.addListener(() {
      // Update preview when text field changes, unless a dropdown item was just selected
      // This avoids a double update if onChanged from dropdown also sets the text field
      if (_selectedIssuer != _issuerController.text) {
        _updatePreviewLogo(_issuerController.text);
        // If user types something that matches an available issuer, select it in dropdown
        if (_availableIssuers.contains(_issuerController.text)) {
          setState(() {
            _selectedIssuer = _issuerController.text;
          });
        } else {
          // If user types something different, clear dropdown selection
          setState(() {
            _selectedIssuer = null;
          });
        }
      }
    });
    _updatePreviewLogo(_issuerController.text); // Initial preview
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    scannerController.dispose(); // Dispose scanner controller
    super.dispose();
  }

  Future<void> _loadAvailableIssuers() async {
    // Ensure LogoService is loaded - it's a singleton, loadLogoMap handles multiple calls
    await LogoService.instance.loadLogoMap();
    if (mounted) {
      setState(() {
        _availableIssuers = LogoService.instance.getAvailableIssuers();
        // Attempt to set initial preview based on controller, if any text exists
        if (_issuerController.text.isNotEmpty) {
          _updatePreviewLogo(_issuerController.text);
          if (_availableIssuers.contains(_issuerController.text)) {
            _selectedIssuer = _issuerController.text;
          }
        }
      });
    }
  }

  void _updatePreviewLogo(String? issuerName) {
    if (mounted) {
      setState(() {
        _previewLogoPath = LogoService.instance.getLogoPath(issuerName);
      });
    }
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
      // Update UI elements after QR scan
      if (mounted) {
        _issuerController.text = issuer ?? '';
        _accountNameController.text =
            label.isNotEmpty ? label : (issuer ?? 'Unknown Account');
        _secretController.text = secret;
        _updatePreviewLogo(issuer);
        if (_availableIssuers.contains(issuer)) {
          setState(() {
            _selectedIssuer = issuer;
          });
        } else {
          setState(() {
            _selectedIssuer = null;
          });
        }
      }
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

  Future<void> _showLogoSelectionDialog() async {
    final String? selectedIssuerFromDialog = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return LogoPickerDialog(
          availableIssuers: _availableIssuers,
          currentIssuer: _issuerController.text,
        );
      },
    );

    if (selectedIssuerFromDialog != null) {
      setState(() {
        _issuerController.text = selectedIssuerFromDialog;
        _selectedIssuer =
            selectedIssuerFromDialog; // Keep this to indicate a choice was made
        _updatePreviewLogo(selectedIssuerFromDialog);
      });
    }
  }

  // --- Function to pick image and analyze QR code ---
  Future<void> _pickAndAnalyzeImage() async {
    final ImagePicker picker = ImagePicker();
    // Pick an image
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) {
      // User cancelled the picker
      debugPrint('Image picking cancelled.');
      return;
    }

    debugPrint('Analyzing image: ${image.path}');
    // Analyze the image
    try {
      // analyzeImage returns BarcodeCapture? not bool
      final BarcodeCapture? barcodeCapture = await scannerController
          .analyzeImage(image.path);

      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        // Barcode found, manually call the handler
        _handleBarcode(barcodeCapture);
      } else {
        // No barcode found in the image
        _showError('No QR code found in the selected image.');
      }
      // If a barcode is found, the onDetect listener (_handleBarcode) will be called automatically.
    } catch (e) {
      debugPrint('Error analyzing image: $e');
      _showError('Could not analyze the selected image.');
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
          // Add "Select Image" button first (only when not scanning)
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.image_outlined),
              tooltip: 'Select QR Code Image',
              onPressed: _pickAndAnalyzeImage, // Call the new function
            ),
          // Toggle Button second
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
            if (_previewLogoPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: InkWell(
                    onTap: _showLogoSelectionDialog,
                    child: Tooltip(
                      message: "Tap to change logo",
                      child: Stack(
                        clipBehavior: Clip.none, // Allow overflow
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width:
                                72, // Increased size for better tap target and icon placement
                            height: 72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child:
                                  _previewLogoPath == null ||
                                          _previewLogoPath!.isEmpty
                                      ? Container(
                                        // Placeholder when no logo is available
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            8.0,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.image_search,
                                          size: 40,
                                          color: Colors.grey,
                                        ),
                                      )
                                      : Image.asset(
                                        _previewLogoPath!,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => Container(
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                              ),
                                              child: const Icon(
                                                Icons.business_center_outlined,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            ),
                                      ),
                            ),
                          ),
                          Positioned(
                            right: -4, // Adjust to make it slightly outside
                            bottom: -4, // Adjust to make it slightly outside
                            child: Container(
                              padding: const EdgeInsets.all(
                                4,
                              ), // Slightly more padding
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context)
                                        .colorScheme
                                        .primary, // Solid primary color background
                                shape: BoxShape.circle,
                                // Optional: Add a slight shadow to make it "pop" more
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    spreadRadius: 1,
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.edit,
                                size:
                                    16, // Slightly smaller icon if padding is increased
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimary, // Ensure contrast
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24), // Increased spacing after logo
            TextFormField(
              controller: _issuerController,
              decoration: InputDecoration(
                labelText: 'Issuer (e.g., Google, GitHub)',
                hintText:
                    _selectedIssuer != null
                        ? 'Selected: $_selectedIssuer'
                        : 'Type to search or add new',
              ),
              validator:
                  (value) =>
                      (value == null || value.isEmpty)
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
