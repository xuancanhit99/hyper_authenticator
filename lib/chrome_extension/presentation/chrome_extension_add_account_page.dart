import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';
import 'package:hyper_authenticator/core/router/app_routes.dart';
import 'package:hyper_authenticator/core/widgets/responsive_content.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';

/// Manual account entry for the Chrome Extension MVP.
///
/// QR scan/import is intentionally unavailable until the ZXing decoder is
/// bundled locally and checked by the MV3 remote-code gate.
class ChromeExtensionAddAccountPage extends StatefulWidget {
  const ChromeExtensionAddAccountPage({super.key});

  @override
  State<ChromeExtensionAddAccountPage> createState() =>
      _ChromeExtensionAddAccountPageState();
}

class _ChromeExtensionAddAccountPageState
    extends State<ChromeExtensionAddAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _secretController = TextEditingController();
  var _isSubmitting = false;
  var _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    _issuerController.addListener(_refreshIssuerPreview);
  }

  @override
  void dispose() {
    _issuerController
      ..removeListener(_refreshIssuerPreview)
      ..dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _refreshIssuerPreview() {
    if (mounted) setState(() {});
  }

  void _submit() {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    context.read<AccountsBloc>().add(
      AddAccountRequested(
        issuer: _issuerController.text.trim(),
        accountName: _accountNameController.text.trim(),
        secretKey: _secretController.text.trim(),
        algorithm: 'SHA1',
        digits: 6,
        period: 30,
      ),
    );
  }

  void _showError(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: colorScheme.onError)),
        backgroundColor: colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thêm mã xác thực')),
    body: BlocListener<AccountsBloc, AccountsState>(
      listener: (context, state) {
        if (state is AccountAddSuccess && _isSubmitting) {
          setState(() => _isSubmitting = false);
          context.go(AppRoutes.main);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Đã thêm mã xác thực.')));
        } else if (state is AccountsError && _isSubmitting) {
          setState(() => _isSubmitting = false);
          _showError(state.message);
        }
      },
      child: MaxWidthContent(
        maxWidth: 640,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
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
                  controller: _issuerController,
                  decoration: const InputDecoration(
                    labelText: AppCopy.service,
                    hintText: AppCopy.serviceExample,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập tên dịch vụ.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _accountNameController,
                  decoration: const InputDecoration(
                    labelText: AppCopy.account,
                    hintText: AppCopy.accountExample,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập tên tài khoản.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _secretController,
                  decoration: InputDecoration(
                    labelText: AppCopy.setupKey,
                    helperText: 'Chuỗi ký tự nằm cạnh mã QR',
                    suffixIcon: IconButton(
                      tooltip: _obscureSecret
                          ? 'Hiện khóa thiết lập'
                          : 'Ẩn khóa thiết lập',
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập khóa thiết lập.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Thêm mã'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
