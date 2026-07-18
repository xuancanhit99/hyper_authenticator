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

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

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
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_canSubmit) Navigator.pop(context, _controller.text);
        },
        decoration: const InputDecoration(
          labelText: 'Recovery key',
          hintText: 'HA1-…',
          helperText: 'Key chỉ được xử lý trong thiết bị này.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _canSubmit
              ? () => Navigator.pop(context, _controller.text)
              : null,
          child: const Text('Khôi phục'),
        ),
      ],
    );
  }
}
