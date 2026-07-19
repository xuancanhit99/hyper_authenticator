import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/device_session_bloc.dart';
import 'package:intl/intl.dart';

class AuthenticatedDevicesTile extends StatefulWidget {
  final UserEntity currentUser;

  const AuthenticatedDevicesTile({super.key, required this.currentUser});

  @override
  State<AuthenticatedDevicesTile> createState() =>
      _AuthenticatedDevicesTileState();
}

class _AuthenticatedDevicesTileState extends State<AuthenticatedDevicesTile> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedDevicesTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.id != widget.currentUser.id) {
      _load();
    }
  }

  void _load() {
    if (!mounted) return;
    context.read<DeviceSessionBloc>().add(
      LoadDeviceSessionsRequested(widget.currentUser.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceSessionBloc, DeviceSessionState>(
      builder: (context, state) {
        final belongsToCurrentUser = state.userId == widget.currentUser.id;
        final loading = !belongsToCurrentUser || state is DeviceSessionLoading;
        final devices = belongsToCurrentUser ? state.devices : const [];
        final subtitle = switch (state) {
          _ when !belongsToCurrentUser => 'Đang đăng ký phiên hiện tại...',
          DeviceSessionLoadFailure(:final message) => message,
          DeviceSessionLoading() => 'Đang đăng ký phiên hiện tại...',
          _ when devices.isEmpty => 'Chưa tải được phiên thiết bị.',
          _ =>
            '${devices.length} phiên đã nhận diện; phiên cũ chưa đăng ký vẫn cần thu hồi hàng loạt.',
        };
        return ListTile(
          leading: loading
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.devices),
          title: const Text('Thiết bị đã đăng nhập'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: loading
              ? null
              : devices.isEmpty
              ? _load
              : () => _showDevices(context),
        );
      },
    );
  }

  Future<void> _showDevices(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<DeviceSessionBloc>(),
      child: _AuthenticatedDevicesDialog(currentUser: widget.currentUser),
    ),
  );
}

class _AuthenticatedDevicesDialog extends StatelessWidget {
  final UserEntity currentUser;

  const _AuthenticatedDevicesDialog({required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceSessionBloc, DeviceSessionState>(
      builder: (context, state) {
        final belongsToCurrentUser = state.userId == currentUser.id;
        final devices = belongsToCurrentUser ? state.devices : const [];
        final revokingId = switch (state) {
          DeviceSessionRevoking(:final registrationId)
              when belongsToCurrentUser =>
            registrationId,
          _ => null,
        };
        return AlertDialog(
          scrollable: true,
          title: const Text('Thiết bị đã đăng nhập'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Danh sách chỉ gồm phiên đã chạy phiên bản có device registry. Thu hồi sẽ đăng xuất phiên cloud; local TOTP trên thiết bị đó không bị xóa.',
              ),
              const SizedBox(height: 12),
              if (!belongsToCurrentUser)
                const Text(
                  'Tài khoản đã thay đổi. Đóng hộp thoại và mở lại danh sách.',
                ),
              for (final device in devices)
                _DeviceSessionRow(
                  device: device,
                  busy: revokingId != null,
                  revoking: revokingId == device.registrationId,
                  onRevoke: () => _confirmRevoke(context, device),
                ),
              if (belongsToCurrentUser &&
                  state is DeviceSessionActionFailure) ...[
                const SizedBox(height: 8),
                Text(
                  state.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: revokingId == null && belongsToCurrentUser
                  ? () => context.read<DeviceSessionBloc>().add(
                      LoadDeviceSessionsRequested(currentUser.id),
                    )
                  : null,
              child: const Text('Tải lại'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: revokingId == null
                  ? () => Navigator.pop(context)
                  : null,
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    AuthenticatorDeviceSession device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Đăng xuất phiên thiết bị?'),
        content: Text(
          '${device.displayName} sẽ mất ngay quyền đọc/ghi encrypted vault và phải đăng nhập lại để kết nối cloud. Local TOTP trên thiết bị đó không bị xóa.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Đăng xuất thiết bị'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<DeviceSessionBloc>().add(
        RevokeDeviceSessionRequested(
          userId: currentUser.id,
          registrationId: device.registrationId,
        ),
      );
    }
  }
}

class _DeviceSessionRow extends StatelessWidget {
  final AuthenticatorDeviceSession device;
  final bool busy;
  final bool revoking;
  final VoidCallback onRevoke;

  const _DeviceSessionRow({
    required this.device,
    required this.busy,
    required this.revoking,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final lastSeen = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(device.lastSeenAt.toLocal());
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_platformIcon(device.platform)),
      title: Text(device.displayName),
      subtitle: Text(
        device.isCurrent
            ? 'Thiết bị này • cập nhật $lastSeen'
            : 'Cập nhật registry $lastSeen',
      ),
      trailing: device.isCurrent
          ? const Chip(label: Text('Hiện tại'))
          : revoking
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: 'Đăng xuất ${device.displayName}',
              onPressed: busy ? null : onRevoke,
              icon: const Icon(Icons.logout, color: Colors.red),
            ),
    );
  }

  IconData _platformIcon(String platform) => switch (platform) {
    'android' => Icons.android,
    'ios' || 'macos' => Icons.apple,
    'windows' => Icons.desktop_windows,
    'linux' => Icons.computer,
    'web' => Icons.language,
    _ => Icons.devices_other,
  };
}
