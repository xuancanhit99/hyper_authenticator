import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum RecoveryKeyOperation { setup, recoveryKeyRotation, vaultKeyRotation }

Future<bool> showRecoveryKeyConfirmationDialog(
  BuildContext context, {
  required String recoveryCode,
  required RecoveryKeyOperation operation,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecoveryKeyConfirmationDialog(
        recoveryCode: recoveryCode,
        operation: operation,
      ),
    ) ??
    false;

class RecoveryKeyConfirmationDialog extends StatefulWidget {
  final String recoveryCode;
  final RecoveryKeyOperation operation;

  const RecoveryKeyConfirmationDialog({
    super.key,
    required this.recoveryCode,
    required this.operation,
  });

  @override
  State<RecoveryKeyConfirmationDialog> createState() =>
      _RecoveryKeyConfirmationDialogState();
}

class _RecoveryKeyConfirmationDialogState
    extends State<RecoveryKeyConfirmationDialog> {
  bool _confirmedSaved = false;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context, false),
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(
          widget.operation == RecoveryKeyOperation.setup
              ? 'Lưu recovery key'
              : 'Lưu recovery key mới',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_warningFor(widget.operation)),
            const SizedBox(height: 16),
            _SensitiveRecoveryKeyPanel(recoveryCode: widget.recoveryCode),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmedSaved,
              onChanged: (value) =>
                  setState(() => _confirmedSaved = value ?? false),
              title: const Text(
                'Tôi đã lưu key vào password manager hoặc nơi an toàn.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: _confirmedSaved
                ? () => Navigator.pop(context, true)
                : null,
            child: Text(_actionFor(widget.operation)),
          ),
        ],
      ),
    );
  }

  String _warningFor(RecoveryKeyOperation operation) => switch (operation) {
    RecoveryKeyOperation.setup =>
      'Key này không được gửi lên server. Mất mọi thiết bị và key sẽ không thể khôi phục cloud vault.',
    RecoveryKeyOperation.recoveryKeyRotation =>
      'Recovery key cũ không thể mở snapshot hiện tại sau khi hoàn tất. Thiết bị đã giữ vault key vẫn tiếp tục hoạt động.',
    RecoveryKeyOperation.vaultKeyRotation =>
      'Cả vault key và recovery key sẽ đổi. Mọi device key đang active có membership proof hợp lệ sẽ nhận wrap cho vault key mới. Thao tác không đăng xuất phiên Supabase, không loại riêng thiết bị và không xóa backup lịch sử.',
  };

  String _actionFor(RecoveryKeyOperation operation) => switch (operation) {
    RecoveryKeyOperation.setup => 'Bật encrypted sync',
    RecoveryKeyOperation.recoveryKeyRotation => 'Xoay recovery key',
    RecoveryKeyOperation.vaultKeyRotation => 'Xoay vault key',
  };
}

class _SensitiveRecoveryKeyPanel extends StatelessWidget {
  final String recoveryCode;

  const _SensitiveRecoveryKeyPanel({required this.recoveryCode});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label: 'Recovery key nhạy cảm',
                hint:
                    'Dùng nút Sao chép recovery key để lưu vào password manager hoặc nơi an toàn.',
                child: SelectableText(
                  recoveryCode,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Sao chép recovery key',
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: recoveryCode));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Đã sao chép recovery key.')),
      );
  }
}
