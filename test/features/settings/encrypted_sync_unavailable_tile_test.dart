import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/encrypted_sync_unavailable_tile.dart';

void main() {
  testWidgets('Web giải thích encrypted sync không hỗ trợ', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EncryptedSyncUnavailableTile())),
    );

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text('Backup cloud mã hóa đầu cuối'), findsOneWidget);
    expect(find.textContaining('Không hỗ trợ trên Web'), findsOneWidget);
    expect(find.text('Đăng nhập để dùng encrypted cloud sync'), findsNothing);
  });

  testWidgets('local-only giải thích cloud chưa được cấu hình', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EncryptedSyncUnavailableTile(
            message:
                'Bản cài này đang chạy local-only. Bạn vẫn có thể thêm và dùng mã TOTP.',
          ),
        ),
      ),
    );

    expect(find.textContaining('local-only'), findsOneWidget);
    expect(find.textContaining('mã TOTP'), findsOneWidget);
  });
}
