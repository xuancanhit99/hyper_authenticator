import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/encrypted_backup_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';
import 'package:intl/intl.dart';

class EncryptedBackupPage extends StatelessWidget {
  const EncryptedBackupPage({super.key, this.bloc});

  final EncryptedBackupBloc? bloc;

  @override
  Widget build(BuildContext context) {
    final providedBloc = bloc;
    if (providedBloc != null) {
      return BlocProvider.value(
        value: providedBloc,
        child: const _EncryptedBackupView(),
      );
    }
    return BlocProvider(
      create: (_) => sl<EncryptedBackupBloc>(),
      child: const _EncryptedBackupView(),
    );
  }
}

class _EncryptedBackupView extends StatefulWidget {
  const _EncryptedBackupView();

  @override
  State<_EncryptedBackupView> createState() => _EncryptedBackupViewState();
}

class _EncryptedBackupViewState extends State<_EncryptedBackupView>
    with WidgetsBindingObserver {
  BuildContext? _activeSensitiveDialogContext;
  Completer<void>? _resumeCompleter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;
      return;
    }
    if (_activeSensitiveDialogContext == null) return;
    final bloc = context.read<EncryptedBackupBloc>();
    if (bloc.state is EncryptedBackupPasswordRequired ||
        bloc.state is EncryptedBackupRestorePreview) {
      _closeSensitiveDialog();
      bloc.add(
        const DiscardEncryptedBackup(
          reason:
              'Phiên import đã đóng vì ứng dụng không còn ở foreground; vault không thay đổi.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<EncryptedBackupBloc, EncryptedBackupState>(
      listener: _handleState,
      builder: (context, state) {
        final busy = state is EncryptedBackupBusy;
        return Scaffold(
          appBar: AppBar(title: const Text('Backup file mã hóa')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SecuritySummaryCard(state: state),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Tạo file backup',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Xuất toàn bộ local vault vào một file .hyauth. File giữ stable ID, thứ tự và đầy đủ TOTP semantics.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('create-encrypted-backup'),
                        onPressed: busy ? null : _requestExportPassword,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Tạo backup mã hóa'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Khôi phục từ file',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Bạn sẽ được xem preview sau khi file vượt qua integrity verification. Xác nhận cuối sẽ thay toàn bộ local vault, không merge.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('pick-encrypted-backup'),
                        onPressed: busy
                            ? null
                            : () => context.read<EncryptedBackupBloc>().add(
                                const PickEncryptedBackupRequested(),
                              ),
                        icon: const Icon(Icons.restore),
                        label: const Text('Chọn file để khôi phục'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _PasswordNotice(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleState(BuildContext _, EncryptedBackupState state) async {
    if (state is EncryptedBackupPasswordRequired) {
      await _waitUntilResumed();
      if (!mounted ||
          context.read<EncryptedBackupBloc>().state
              is! EncryptedBackupPasswordRequired) {
        return;
      }
      final password = await _showSensitiveDialog<String>(
        (dialogContext) => _BackupPasswordDialog(
          title: 'Mở file backup',
          actionLabel: 'Xác minh file',
          confirmPassword: false,
          dialogContext: dialogContext,
        ),
        barrierDismissible: false,
      );
      if (!mounted ||
          context.read<EncryptedBackupBloc>().state
              is! EncryptedBackupPasswordRequired) {
        return;
      }
      if (password == null) {
        context.read<EncryptedBackupBloc>().add(const DiscardEncryptedBackup());
      } else {
        context.read<EncryptedBackupBloc>().add(
          DecryptEncryptedBackupRequested(password),
        );
      }
      return;
    }
    if (state is EncryptedBackupRestorePreview) {
      await _waitUntilResumed();
      if (!mounted) return;
      final resumedState = context.read<EncryptedBackupBloc>().state;
      if (resumedState is! EncryptedBackupRestorePreview ||
          resumedState.token != state.token) {
        return;
      }
      final confirmed = await _showSensitiveDialog<bool>(
        (dialogContext) =>
            _RestoreBackupDialog(preview: state, dialogContext: dialogContext),
        barrierDismissible: false,
      );
      if (!mounted) return;
      final currentState = context.read<EncryptedBackupBloc>().state;
      if (currentState is! EncryptedBackupRestorePreview ||
          currentState.token != state.token) {
        return;
      }
      if (confirmed == true) {
        context.read<EncryptedBackupBloc>().add(
          ConfirmEncryptedBackupRestore(state.token),
        );
      } else {
        context.read<EncryptedBackupBloc>().add(const DiscardEncryptedBackup());
      }
      return;
    }
    if (state is EncryptedBackupSuccess ||
        state is EncryptedBackupFailure ||
        state is EncryptedBackupCancelled) {
      _closeSensitiveDialog();
      final message = switch (state) {
        EncryptedBackupSuccess(:final message) => message,
        EncryptedBackupFailure(:final message) => message,
        EncryptedBackupCancelled(:final message) => message,
        _ => '',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      if (state is EncryptedBackupSuccess && state.restored) {
        context.read<AccountsBloc>().add(LoadAccounts());
      }
    }
  }

  Future<void> _requestExportPassword() async {
    final password = await _showSensitiveDialog<String>(
      (dialogContext) => _BackupPasswordDialog(
        title: 'Đặt password cho backup',
        actionLabel: 'Mã hóa và lưu',
        confirmPassword: true,
        dialogContext: dialogContext,
      ),
    );
    if (!mounted || password == null) return;
    context.read<EncryptedBackupBloc>().add(
      CreateEncryptedBackupRequested(password),
    );
  }

  Future<T?> _showSensitiveDialog<T>(
    Widget Function(BuildContext dialogContext) builder, {
    bool barrierDismissible = true,
  }) async {
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (dialogContext) {
          _activeSensitiveDialogContext = dialogContext;
          return builder(dialogContext);
        },
      );
    } finally {
      _activeSensitiveDialogContext = null;
    }
  }

  Future<void> _waitUntilResumed() async {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      _resumeCompleter ??= Completer<void>();
      await _resumeCompleter!.future;
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
  }

  void _closeSensitiveDialog() {
    final dialogContext = _activeSensitiveDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      final navigator = Navigator.of(dialogContext);
      final route = ModalRoute.of(dialogContext);
      if (route == null) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }
    _activeSensitiveDialogContext = null;
  }
}

class _SecuritySummaryCard extends StatelessWidget {
  const _SecuritySummaryCard({required this.state});

  final EncryptedBackupState state;

  @override
  Widget build(BuildContext context) {
    final status = state is EncryptedBackupBusy
        ? (state as EncryptedBackupBusy).message
        : 'Argon2id v19 · AES-256-GCM · schema v1 · atomic restore';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          container: true,
          liveRegion: state is EncryptedBackupBusy,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state is EncryptedBackupBusy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.enhanced_encryption),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Portable và không phụ thuộc Supabase',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(status),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordNotice extends StatelessWidget {
  const _PasswordNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ứng dụng không lưu và không thể lấy lại password. Password được dùng nguyên văn, không tự trim hay normalize. Hãy cất password tách biệt với file backup.',
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({
    required this.title,
    required this.actionLabel,
    required this.confirmPassword,
    required this.dialogContext,
  });

  final String title;
  final String actionLabel;
  final bool confirmPassword;
  final BuildContext dialogContext;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('backup-password'),
                controller: _passwordController,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofocus: true,
                textInputAction: widget.confirmPassword
                    ? TextInputAction.next
                    : TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Password backup',
                  helperText:
                      'Tối thiểu 12 ký tự; khoảng trắng được giữ nguyên.',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Hiện password' : 'Ẩn password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: _validatePassword,
                onFieldSubmitted: widget.confirmPassword
                    ? null
                    : (_) => _submit(),
              ),
              if (widget.confirmPassword) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('backup-password-confirmation'),
                  controller: _confirmationController,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Nhập lại password',
                  ),
                  validator: (value) => value == _passwordController.text
                      ? null
                      : 'Hai password không giống nhau.',
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(widget.dialogContext).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('submit-backup-password'),
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.runes.length < 12 || utf8.encode(password).length > 1024) {
      return 'Password phải có ít nhất 12 ký tự và không quá 1.024 byte.';
    }
    if (password.trim().isEmpty) {
      return 'Password không được chỉ có khoảng trắng.';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(widget.dialogContext).pop(_passwordController.text);
  }
}

class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog({
    required this.preview,
    required this.dialogContext,
  });

  final EncryptedBackupRestorePreview preview;
  final BuildContext dialogContext;

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  static const _confirmationPhrase = 'KHOI PHUC';
  final _confirmationController = TextEditingController();
  bool _canRestore = false;

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final visibleAccounts = preview.accounts.take(50).toList(growable: false);
    final remaining = preview.accounts.length - visibleAccounts.length;
    return AlertDialog(
      title: const Text('Thay toàn bộ local vault?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Backup ${DateFormat.yMd().add_Hm().format(preview.createdAt.toLocal())}',
              ),
              const SizedBox(height: 6),
              Text(
                '${preview.currentAccountCount} tài khoản hiện tại → ${preview.accounts.length} tài khoản từ backup',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Integrity verification đã pass. Kiểm tra danh sách trước khi tiếp tục:',
              ),
              const SizedBox(height: 8),
              for (final account in visibleAccounts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key, size: 20),
                  title: Text(account.issuer),
                  subtitle: Text(
                    '${account.accountName} · ${account.algorithm} · ${account.digits} số · ${account.period}s',
                  ),
                ),
              if (remaining > 0)
                Text(
                  '… và $remaining tài khoản khác.',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              const SizedBox(height: 12),
              Text(
                'Gõ $_confirmationPhrase để cho phép atomic replacement:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('restore-confirmation-phrase'),
                controller: _confirmationController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: _confirmationPhrase,
                ),
                onChanged: (value) =>
                    setState(() => _canRestore = value == _confirmationPhrase),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(widget.dialogContext).pop(false),
          child: const Text('Giữ vault hiện tại'),
        ),
        FilledButton(
          key: const Key('confirm-atomic-restore'),
          onPressed: _canRestore
              ? () => Navigator.of(widget.dialogContext).pop(true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Thay local vault'),
        ),
      ],
    );
  }
}
