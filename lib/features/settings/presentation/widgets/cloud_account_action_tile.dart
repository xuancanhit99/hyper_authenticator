import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_routes.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';

/// Entry point tối giản cho tài khoản dùng bởi đồng bộ cloud tự động.
///
/// Widget này không quản lý session/device từ xa. Đăng xuất chỉ kết thúc phiên
/// cloud; local TOTP vault và app lock thuộc subsystem khác và được giữ nguyên.
class CloudAccountActionTile extends StatelessWidget {
  final UserEntity? currentUser;

  const CloudAccountActionTile({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return ListTile(
        key: const Key('cloud-sign-in-action'),
        leading: const Icon(Icons.login),
        title: const Text('Đăng nhập để đồng bộ'),
        subtitle: const Text(
          'Bạn vẫn có thể dùng mã trên thiết bị này khi chưa đăng nhập.',
        ),
        onTap: () => context.push(
          Uri(
            path: AppRoutes.login,
            queryParameters: {'returnTo': AppRoutes.settings},
          ).toString(),
        ),
      );
    }

    final destructiveColor = Theme.of(context).colorScheme.error;
    return ListTile(
      key: const Key('cloud-sign-out-action'),
      leading: Icon(Icons.logout, color: destructiveColor),
      title: Text('Đăng xuất', style: TextStyle(color: destructiveColor)),
      subtitle: const Text('Các mã trên thiết bị này vẫn được giữ lại.'),
      onTap: () => _confirmLogout(context),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Xác nhận đăng xuất'),
        content: const Text(
          'Bạn sẽ ngừng đồng bộ trên thiết bị này. Các mã đã lưu vẫn được giữ lại.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(AuthSignOutRequested());
    }
  }
}
