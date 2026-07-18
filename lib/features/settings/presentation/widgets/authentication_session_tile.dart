import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/session_security_bloc.dart';

class AuthenticationSessionTile extends StatelessWidget {
  final UserEntity? currentUser;
  final SessionSecurityState sessionSecurityState;

  const AuthenticationSessionTile({
    super.key,
    required this.currentUser,
    required this.sessionSecurityState,
  });

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return ListTile(
        leading: const Icon(Icons.login),
        title: const Text('Đăng nhập để dùng encrypted cloud sync'),
        subtitle: const Text('Local vault vẫn hoạt động khi offline.'),
        onTap: () => context.push(
          Uri(
            path: AppRoutes.login,
            queryParameters: {'returnTo': AppRoutes.settings},
          ).toString(),
        ),
      );
    }
    final revoking = sessionSecurityState is SessionSecurityInProgress;
    return Column(
      children: [
        ListTile(
          leading: revoking
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.phonelink_erase),
          title: const Text('Đăng xuất các phiên khác'),
          subtitle: const Text(
            'Giữ phiên này; thu hồi quyền truy cập encrypted vault của các phiên khác.',
          ),
          onTap: revoking ? null : () => _confirmRevokeOtherSessions(context),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
          subtitle: const Text('Local vault và app lock được giữ nguyên.'),
          onTap: () => _confirmLogout(context),
        ),
      ],
    );
  }

  Future<void> _confirmRevokeOtherSessions(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đăng xuất các phiên khác?'),
        content: const Text(
          'Thiết bị này vẫn đăng nhập. Các phiên khác bị hủy refresh token và server chặn ngay quyền đọc/ghi encrypted vault. Local vault và vault key trên thiết bị này không thay đổi.\n\nNếu nghi một thiết bị đã bị lộ, hãy xoay vault key trước khi thực hiện bước này để thu hồi cả khả năng giải mã snapshot mới.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đăng xuất phiên khác'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<SessionSecurityBloc>().add(
        const RevokeOtherSessionsRequested(),
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text(
          'Dữ liệu TOTP local không bị xóa. Vault key vẫn được giữ trong secure storage của thiết bị này.',
        ),
        actions: [
          TextButton(
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
