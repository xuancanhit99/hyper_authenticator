import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/config/app_metadata.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';

class ProductInfoTile extends StatelessWidget {
  const ProductInfoTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('product-info-tile'),
      leading: const Icon(Icons.info_outline),
      title: const Text(AppCopy.about),
      subtitle: const Text('${AppCopy.appName} · ${AppMetadata.versionLabel}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showProductInfo(context),
    );
  }

  Future<void> _showProductInfo(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _ProductInfoSheet(),
    );
  }
}

class _ProductInfoSheet extends StatelessWidget {
  const _ProductInfoSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppCopy.appName,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const Key('close-product-info-sheet'),
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(AppMetadata.versionLabel),
                const SizedBox(height: 16),
                Text(
                  'Tạo mã xác thực dùng một lần, kể cả khi không có mạng.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                const _InfoRow(
                  icon: Icons.phone_android_outlined,
                  title: 'Dùng không cần tài khoản',
                  description:
                      'Không đăng nhập, các mã chỉ được lưu trên thiết bị này.',
                ),
                const _InfoRow(
                  icon: Icons.sync_outlined,
                  title: 'Đồng bộ khi đăng nhập',
                  description:
                      'Các mã tự cập nhật trên những thiết bị dùng cùng tài khoản.',
                ),
                const _InfoRow(
                  icon: Icons.lock_outline,
                  title: 'Bảo vệ dữ liệu',
                  description:
                      'Dữ liệu đồng bộ được mã hóa khi lưu. Dịch vụ đồng bộ có thể xử lý dữ liệu để chuyển giữa các thiết bị.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('open-source-licenses-action'),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppCopy.appName,
                    applicationVersion: AppMetadata.versionLabel,
                    applicationIcon: const Icon(
                      Icons.shield_outlined,
                      size: 48,
                    ),
                  ),
                  icon: const Icon(Icons.code),
                  label: const Text('Giấy phép mã nguồn mở'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
    );
  }
}
