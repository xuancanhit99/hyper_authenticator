import 'package:flutter/material.dart';

Future<String?> showRecoveryImportDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const RecoveryImportDialog(),
    );

class RecoveryImportDialog extends StatefulWidget {
  const RecoveryImportDialog({super.key});

  @override
  State<RecoveryImportDialog> createState() => _RecoveryImportDialogState();
}

class _RecoveryImportDialogState extends State<RecoveryImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nhập recovery key'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'HA1-…',
          helperText: 'Key chỉ được xử lý trong thiết bị này.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Khôi phục'),
        ),
      ],
    );
  }
}
