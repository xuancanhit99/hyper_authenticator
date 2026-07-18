import 'package:flutter/material.dart';

class EncryptedSyncUnavailableTile extends StatelessWidget {
  const EncryptedSyncUnavailableTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(Icons.cloud_off),
        title: Text('Encrypted cloud sync'),
        subtitle: Text(
          'Không hỗ trợ trên Web vì browser storage không có trust boundary tương đương secure storage native.',
        ),
      ),
    );
  }
}
