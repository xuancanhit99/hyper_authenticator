import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/core/widgets/responsive_content.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';

class EditAccountPage extends StatefulWidget {
  static const submitButtonKey = Key('edit-account-submit');
  static const issuerFieldKey = Key('edit-account-issuer');
  static const accountNameFieldKey = Key('edit-account-name');
  static const secretFieldKey = Key('edit-account-secret');
  static const algorithmFieldKey = Key('edit-account-algorithm');
  static const digitsFieldKey = Key('edit-account-digits');
  static const periodFieldKey = Key('edit-account-period');

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
  bool _isSubmitting = false;
  bool _obscureSecret = true;
  Object? _activeOperationToken;

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
    _algorithmController.dispose();
    _digitsController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  void _submitUpdate() {
    if (_isSubmitting) {
      return;
    }
    if (_formKey.currentState!.validate()) {
      final updatedAccount = AuthenticatorAccount(
        id: widget.account.id, // Keep the original ID
        issuer: _issuerController.text.trim(),
        accountName: _accountNameController.text.trim(),
        secretKey: _secretController.text
            .trim(), // Secret key modification might be risky/complex in real 2FA
        algorithm: _algorithmController.text.trim().toUpperCase(),
        digits:
            int.tryParse(_digitsController.text.trim()) ??
            widget.account.digits,
        period:
            int.tryParse(_periodController.text.trim()) ??
            widget.account.period,
      );

      final operationToken = Object();
      setState(() {
        _isSubmitting = true;
        _activeOperationToken = operationToken;
      });
      context.read<AccountsBloc>().add(
        UpdateAccountRequested(
          account: updatedAccount,
          operationToken: operationToken,
        ),
      );
    }
  }

  void _finishSuccessfulUpdate() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isSubmitting = false;
      _activeOperationToken = null;
    });
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
    messenger.showSnackBar(
      const SnackBar(content: Text('Đã cập nhật tài khoản.')),
    );
  }

  void _showError(String message) {
    if (mounted) {
      final colorScheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: colorScheme.onError)),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: const Text('Chỉnh sửa tài khoản'),
      ),
      body: BlocListener<AccountsBloc, AccountsState>(
        listener: (context, state) {
          if (state is AccountUpdateSuccess &&
              _isSubmitting &&
              identical(state.operationToken, _activeOperationToken)) {
            _finishSuccessfulUpdate();
          } else if (state is AccountUpdateFailure &&
              _isSubmitting &&
              identical(state.operationToken, _activeOperationToken)) {
            if (mounted) {
              setState(() {
                _isSubmitting = false;
                _activeOperationToken = null;
              });
              _showError('Không thể cập nhật tài khoản: ${state.message}');
            }
          }
        },
        child: MaxWidthContent(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: 64 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: AccountAvatar(
                        issuer: _issuerController.text,
                        size: 72,
                      ),
                    ),
                  ),
                  TextFormField(
                    key: EditAccountPage.issuerFieldKey,
                    controller: _issuerController,
                    decoration: const InputDecoration(
                      labelText: 'Nhà cung cấp (ví dụ: Google, GitHub)',
                      hintText: 'Nhập tên nhà cung cấp',
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Vui lòng nhập nhà cung cấp.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: EditAccountPage.accountNameFieldKey,
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
                    key: EditAccountPage.secretFieldKey,
                    controller: _secretController,
                    decoration: InputDecoration(
                      labelText: 'Secret key (mã hóa Base32)',
                      suffixIcon: IconButton(
                        tooltip: _obscureSecret
                            ? 'Hiện secret key'
                            : 'Ẩn secret key',
                        icon: Icon(
                          _obscureSecret
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureSecret = !_obscureSecret),
                      ),
                    ),
                    obscureText: _obscureSecret,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập secret key.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Tùy chọn nâng cao (chỉ sửa khi hiểu rõ):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: EditAccountPage.algorithmFieldKey,
                    controller: _algorithmController,
                    decoration: const InputDecoration(
                      labelText: 'Thuật toán (SHA1, SHA256, SHA512)',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập thuật toán.';
                      }
                      if (![
                        'SHA1',
                        'SHA256',
                        'SHA512',
                      ].contains(value.toUpperCase())) {
                        return 'Thuật toán không hợp lệ. Dùng SHA1, SHA256 hoặc SHA512.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: EditAccountPage.digitsFieldKey,
                    controller: _digitsController,
                    decoration: const InputDecoration(
                      labelText: 'Số chữ số (ví dụ: 6 hoặc 8)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập số chữ số.';
                      }
                      final n = int.tryParse(value);
                      if (n == null) return 'Số không hợp lệ.';
                      if (n < 6 || n > 8) {
                        return 'Số chữ số phải là 6, 7 hoặc 8.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: EditAccountPage.periodFieldKey,
                    controller: _periodController,
                    decoration: const InputDecoration(
                      labelText: 'Chu kỳ (giây, ví dụ: 30)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập chu kỳ.';
                      }
                      final n = int.tryParse(value);
                      if (n == null || n <= 0) {
                        return 'Chu kỳ phải là số dương.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    key: EditAccountPage.submitButtonKey,
                    onPressed: _isSubmitting ? null : _submitUpdate,
                    child: Text(_isSubmitting ? 'Đang lưu…' : 'Lưu thay đổi'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
