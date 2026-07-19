import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key, this.scannerController});

  static const issuerFieldKey = ValueKey<String>('add-account-issuer');
  static const accountNameFieldKey = ValueKey<String>('add-account-name');
  static const secretFieldKey = ValueKey<String>('add-account-secret');
  static const submitButtonKey = ValueKey<String>('add-account-submit');
  static const scannerLoadingKey = ValueKey<String>('scanner-loading');
  static const scannerErrorKey = ValueKey<String>('scanner-error');
  static const scannerRetryKey = ValueKey<String>('scanner-retry');
  static const scannerManualEntryKey = ValueKey<String>('scanner-manual-entry');

  @visibleForTesting
  final MobileScannerController? scannerController;

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _secretController = TextEditingController();

  bool _isScanning = false;
  bool _isSubmitting = false;
  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController =
        widget.scannerController ?? MobileScannerController(autoStart: false);
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
    unawaited(_scannerController.dispose());
    super.dispose();
  }

  void _toggleScanner() {
    if (_isScanning) {
      _showManualEntry();
      return;
    }

    setState(() {
      _isScanning = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isScanning) {
        unawaited(_scannerController.start());
      }
    });
  }

  void _showManualEntry() {
    unawaited(_scannerController.stop());
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _retryScanner() async {
    await _scannerController.stop();
    if (mounted && _isScanning) {
      await _scannerController.start();
    }
  }

  void _handleBarcode(BarcodeCapture capture) {
    unawaited(_scannerController.stop());
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
      _requestAdd(
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
      _requestAdd(
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

  void _requestAdd(AddAccountRequested event) {
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    context.read<AccountsBloc>().add(event);
  }

  void _finishSuccessfulAdd() {
    if (!mounted) {
      return;
    }
    setState(() => _isSubmitting = false);
    if (ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.main);
      }
    } else {
      Navigator.of(context).maybePop();
    }
    messenger.showSnackBar(const SnackBar(content: Text('Đã thêm tài khoản.')));
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
      final BarcodeCapture? barcodeCapture = await _scannerController
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
        title: Text(_isScanning ? 'Quét mã QR' : 'Thêm tài khoản'),
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
              onPressed: _toggleScanner,
            ),
        ],
      ),
      body: BlocListener<AccountsBloc, AccountsState>(
        listener: (context, state) {
          if (state is AccountAddSuccess) {
            _finishSuccessfulAdd();
          } else if (state is AccountsError && _isSubmitting) {
            if (mounted) {
              setState(() => _isSubmitting = false);
              _showError('Không thể thêm tài khoản: ${state.message}');
              if (_isScanning && mounted) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) unawaited(_scannerController.start());
                });
              }
            }
          }
        },
        child: _isScanning ? _buildScannerView() : _buildManualEntryForm(),
      ),
    );
  }

  Widget _buildScannerView() {
    return MobileScanner(
      controller: _scannerController,
      onDetect: _handleBarcode,
      placeholderBuilder: (_) => const _ScannerLoadingView(),
      errorBuilder: (_, error) => _ScannerErrorView(
        message: _scannerErrorMessage(error.errorCode),
        onRetry: _retryScanner,
        onManualEntry: _showManualEntry,
      ),
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
              key: AddAccountPage.issuerFieldKey,
              controller: _issuerController,
              decoration: const InputDecoration(
                labelText: 'Nhà cung cấp (ví dụ: Google, GitHub)',
                hintText: 'Nhập tên nhà cung cấp',
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Vui lòng nhập nhà cung cấp.'
                  : null,
              // Listener is in initState to update preview dynamically
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: AddAccountPage.accountNameFieldKey,
              controller: _accountNameController,
              decoration: const InputDecoration(
                labelText: 'Tên tài khoản (ví dụ: user@example.com)',
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Vui lòng nhập tên tài khoản.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: AddAccountPage.secretFieldKey,
              controller: _secretController,
              decoration: const InputDecoration(
                labelText: 'Secret key (mã hóa Base32)',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập secret key.';
                }
                // Optional: Add a more robust Base32 validation if needed
                return null;
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              key: AddAccountPage.submitButtonKey,
              onPressed: _isSubmitting ? null : _submitManualEntry,
              child: Text(_isSubmitting ? 'Đang thêm…' : 'Thêm tài khoản'),
            ),
          ],
        ),
      ),
    );
  }
}

String _scannerErrorMessage(MobileScannerErrorCode errorCode) {
  return switch (errorCode) {
    MobileScannerErrorCode.permissionDenied =>
      'Ứng dụng chưa có quyền dùng camera. Hãy cho phép camera trong cài đặt '
          'của trình duyệt hoặc hệ điều hành rồi thử lại.',
    MobileScannerErrorCode.unsupported =>
      'Thiết bị hoặc trình duyệt này không hỗ trợ quét mã QR bằng camera.',
    _ =>
      'Không thể khởi động camera. Hãy kiểm tra camera đang không bị ứng dụng '
          'khác sử dụng rồi thử lại.',
  };
}

class _ScannerLoadingView extends StatelessWidget {
  const _ScannerLoadingView();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: AddAccountPage.scannerLoadingKey,
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Đang khởi động camera…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                'Nếu trình duyệt hoặc hệ điều hành hỏi quyền camera, hãy chọn Cho phép.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({
    required this.message,
    required this.onRetry,
    required this.onManualEntry,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: AddAccountPage.scannerErrorKey,
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: AddAccountPage.scannerManualEntryKey,
                    onPressed: onManualEntry,
                    child: const Text('Nhập thủ công'),
                  ),
                  FilledButton(
                    key: AddAccountPage.scannerRetryKey,
                    onPressed: () => unawaited(onRetry()),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
