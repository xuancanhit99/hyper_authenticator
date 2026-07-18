import 'package:flutter/material.dart';

Future<bool> showSyncConflictResolutionDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => SyncConflictResolutionDialog(
        title: title,
        message: message,
        action: action,
      ),
    ) ??
    false;

class SyncConflictResolutionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String action;

  const SyncConflictResolutionDialog({
    super.key,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    );
  }
}
