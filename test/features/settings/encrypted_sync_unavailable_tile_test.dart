import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/encrypted_sync_unavailable_tile.dart';

void main() {
  testWidgets('Web giải thích encrypted sync không hỗ trợ', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EncryptedSyncUnavailableTile())),
    );

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text('Encrypted cloud sync'), findsOneWidget);
    expect(find.textContaining('Không hỗ trợ trên Web'), findsOneWidget);
    expect(find.text('Đăng nhập để dùng encrypted cloud sync'), findsNothing);
  });
}
