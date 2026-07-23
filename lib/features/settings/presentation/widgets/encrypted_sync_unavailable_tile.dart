import 'package:flutter/material.dart';

class EncryptedSyncUnavailableTile extends StatelessWidget {
  const EncryptedSyncUnavailableTile({
    super.key,
    this.message =
        'Không hỗ trợ trên Web vì browser storage không có trust boundary tương đương secure storage native.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.cloud_off),
        title: const Text('Backup cloud mã hóa đầu cuối'),
        subtitle: Text(message),
      ),
    );
  }
}
