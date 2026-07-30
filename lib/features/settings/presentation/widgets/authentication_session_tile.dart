import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/session_security_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/settings_expansion_tile.dart';

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
        title: const Text('Đăng nhập để dùng backup cloud'),
        subtitle: const Text('Mã TOTP local vẫn hoạt động khi offline.'),
        onTap: () => context.push(
          Uri(
            path: AppRoutes.login,
            queryParameters: {'returnTo': AppRoutes.settings},
          ).toString(),
        ),
      );
    }
    final revoking = sessionSecurityState is SessionSecurityInProgress;
    final destructiveColor = Theme.of(context).colorScheme.error;
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.logout, color: destructiveColor),
          title: Text('Đăng xuất', style: TextStyle(color: destructiveColor)),
          subtitle: const Text('Mã TOTP local và app lock được giữ nguyên.'),
          onTap: () => _confirmLogout(context),
        ),
        Divider(
          height: 1,
          indent: 56,
          endIndent: 24,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        SettingsExpansionTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Bảo mật tài khoản nâng cao'),
          subtitle: const Text('Quản lý phiên đăng nhập Supabase.'),
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
                'Giữ phiên này và thu hồi quyền cloud của các phiên khác.',
              ),
              onTap: revoking
                  ? null
                  : () => _confirmRevokeOtherSessions(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRevokeOtherSessions(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Đăng xuất các phiên khác?'),
        content: const Text(
          'Thiết bị này vẫn đăng nhập. Các phiên khác bị hủy refresh token và server chặn ngay quyền đọc/ghi encrypted vault. Local vault và vault key trên các thiết bị không bị xóa.\n\nĐây là thu hồi phiên Supabase, không phải remote wipe hay loại device key khỏi lần xoay vault key kế tiếp. Thiết bị khác vẫn có thể đăng nhập lại.',
        ),
        actions: [
          TextButton(
            autofocus: true,
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
        scrollable: true,
        title: const Text('Xác nhận đăng xuất'),
        content: const Text(
          'Dữ liệu TOTP local không bị xóa. Vault key vẫn được giữ trong secure storage của thiết bị này.',
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
