import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'component gallery ${style.name}/${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final previousDisableShadows = debugDisableShadows;
          debugDisableShadows = true;
          addTearDown(() => debugDisableShadows = previousDisableShadows);

          final theme = brightness == Brightness.light
              ? AppTheme.light(style)
              : AppTheme.dark(style);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: const _ComponentGallery(),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(
            find.byKey(const Key('theme-component-gallery')),
            matchesGoldenFile(
              'goldens/app_theme_${style.name}_${brightness.name}'
              '${Platform.isLinux ? '_linux' : ''}.png',
            ),
          );
        },
        skip: !_supportsGoldenPlatform,
      );
    }
  }
}

final bool _supportsGoldenPlatform = Platform.isMacOS || Platform.isLinux;

class _ComponentGallery extends StatelessWidget {
  const _ComponentGallery();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('theme-component-gallery'),
      appBar: AppBar(title: const Text('Mã xác thực')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tài khoản của bạn',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Text('H'),
              ),
              title: const Text('HyperZ'),
              subtitle: const Text('user@example.com'),
              trailing: Text(
                '123 456',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Dịch vụ',
              hintText: 'Ví dụ: Google',
              prefixIcon: Icon(Icons.shield_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _noop, child: const Text('Lưu')),
              OutlinedButton(onPressed: _noop, child: const Text('Hủy')),
              ElevatedButton(onPressed: _noop, child: const Text('Thử lại')),
            ],
          ),
          const SizedBox(height: 16),
          const Card(
            child: SwitchListTile(
              secondary: Icon(Icons.fingerprint),
              title: Text('Khóa bằng sinh trắc học'),
              subtitle: Text('Dùng khóa màn hình của thiết bị.'),
              value: true,
              onChanged: _ignoreBool,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: colors.errorContainer,
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: colors.error),
              title: const Text('Mã QR chứa khóa thiết lập'),
              subtitle: const Text('Chỉ chia sẻ với thiết bị của bạn.'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            label: 'Tài khoản',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}

void _noop() {}

void _ignoreBool(bool _) {}
