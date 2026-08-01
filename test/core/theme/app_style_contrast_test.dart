import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

// WCAG text-contrast sweep trên control đại diện cho CẢ 6 theme thực tế,
// không chỉ style mặc định như các widget test theo màn hình.
void main() {
  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.light
          ? AppTheme.light(style)
          : AppTheme.dark(style);

      testWidgets('${style.name}/${brightness.name} pass text contrast', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Cài đặt')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Card(
                      child: ListTile(
                        title: Text('Tài khoản'),
                        subtitle: Text('Phụ đề mô tả trạng thái.'),
                      ),
                    ),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: 'Recovery key',
                        helperText: 'Key chỉ được xử lý trong thiết bị này.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () {}, child: const Text('Đồng ý')),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Chính'),
                    ),
                    OutlinedButton(onPressed: () {}, child: const Text('Phụ')),
                    TextButton(onPressed: () {}, child: const Text('Hủy')),
                  ],
                ),
              ),
            ),
          ),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  }
}
