import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/utils/logo_service.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/logo_picker_dialog.dart';
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

  String? _selectedIssuer;
  List<String> _availableIssuers = [];
  String? _previewLogoPath;

  bool _isScanning = false;
  final MobileScannerController scannerController = MobileScannerController(
    autoStart: false,
  );

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
      _updatePreviewLogo(account.issuer);
      setState(() {
        _selectedIssuer = _availableIssuers.contains(account.issuer)
            ? account.issuer
            : null;
      });
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary, // Solid primary color background
                                shape: BoxShape.circle,
                                // Optional: Add a slight shadow to make it "pop" more
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
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
                                color: Theme.of(
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
                hintText: _selectedIssuer != null
                    ? 'Selected: $_selectedIssuer'
                    : 'Type to search or add new',
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
