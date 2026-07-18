import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/encrypted_sync_unavailable_tile.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/recovery_import_dialog.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';
import 'package:intl/intl.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<SettingsBloc>()..add(LoadSettings())),
        BlocProvider(create: (_) => sl<SyncBloc>()),
      ],
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final currentUser = authState is AuthAuthenticated ? authState.user : null;
    final encryptedSyncSupported =
        PlatformCapabilities.supportsEncryptedCloudSync;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (state is SettingsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final loaded = state is SettingsLoaded ? state : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (currentUser != null) _UserCard(currentUser),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('Khóa bằng sinh trắc học'),
                      subtitle: Text(
                        loaded?.canCheckBiometrics == true
                            ? 'Dùng Face ID, vân tay hoặc mã khóa thiết bị.'
                            : 'Thiết bị hoặc platform không hỗ trợ.',
                      ),
                      trailing: loaded?.canCheckBiometrics == true
                          ? Switch(
                              value: loaded!.isBiometricEnabled,
                              onChanged: (enabled) => context
                                  .read<SettingsBloc>()
                                  .add(ToggleBiometric(isEnabled: enabled)),
                            )
                          : null,
                    ),
                    const Divider(height: 1),
                    _EncryptedSyncSection(
                      currentUser: currentUser,
                      isSupported: encryptedSyncSupported,
                    ),
                    if (currentUser != null || encryptedSyncSupported) ...[
                      const Divider(height: 1),
                      _AuthenticationTile(currentUser: currentUser),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserEntity user;

  const _UserCard(this.user);

  @override
  Widget build(BuildContext context) {
    final name = user.name?.trim();
    final email = user.email?.trim();
    final label = name?.isNotEmpty == true
        ? name!
        : email?.isNotEmpty == true
        ? email!
        : 'Tài khoản Supabase';
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(label.characters.first.toUpperCase()),
        ),
        title: Text(label),
        subtitle: email?.isNotEmpty == true ? Text(email!) : null,
      ),
    );
  }
}

class _AuthenticationTile extends StatelessWidget {
  final UserEntity? currentUser;

  const _AuthenticationTile({required this.currentUser});

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
    return ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
      subtitle: const Text('Local vault và app lock được giữ nguyên.'),
      onTap: () => _confirmLogout(context),
    );
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

class _EncryptedSyncSection extends StatefulWidget {
  final UserEntity? currentUser;
  final bool isSupported;

  const _EncryptedSyncSection({
    required this.currentUser,
    required this.isSupported,
  });

  @override
  State<_EncryptedSyncSection> createState() => _EncryptedSyncSectionState();
}

class _EncryptedSyncSectionState extends State<_EncryptedSyncSection> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = context.read<AuthBloc>().stream.listen((state) {
      if (mounted && widget.isSupported && state is AuthAuthenticated) {
        context.read<SyncBloc>().add(const CheckSyncStatus());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isSupported && widget.currentUser != null) {
        context.read<SyncBloc>().add(const CheckSyncStatus());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _EncryptedSyncSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSupported &&
        oldWidget.currentUser?.id != widget.currentUser?.id &&
        widget.currentUser != null) {
      context.read<SyncBloc>().add(const CheckSyncStatus());
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSupported) {
      return const EncryptedSyncUnavailableTile();
    }

    return BlocConsumer<SyncBloc, SyncState>(
      listener: (context, state) async {
        if (state is SyncRecoveryKeyReady) {
          await _showRecoveryKeyDialog(
            context,
            state.recoveryCode,
            operation: _RecoveryKeyOperation.setup,
          );
        } else if (state is SyncRecoveryKeyRotationReady) {
          await _showRecoveryKeyDialog(
            context,
            state.recoveryCode,
            operation: _RecoveryKeyOperation.recoveryKeyRotation,
          );
        } else if (state is SyncVaultKeyRotationReady) {
          await _showRecoveryKeyDialog(
            context,
            state.recoveryCode,
            operation: _RecoveryKeyOperation.vaultKeyRotation,
          );
        } else if (state is SyncSuccess) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Encrypted sync hoàn tất ở revision ${state.revision}.',
                ),
              ),
            );
        } else if (state is SyncFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.enhanced_encryption),
              title: const Text('Encrypted cloud sync'),
              subtitle: _statusText(context, state),
              trailing: state is SyncReady
                  ? Switch(
                      value: state.isEnabled,
                      onChanged: (enabled) => context.read<SyncBloc>().add(
                        SetEncryptedSyncEnabled(enabled),
                      ),
                    )
                  : null,
            ),
            if (widget.currentUser != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: _actions(context, state),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusText(BuildContext context, SyncState state) {
    return switch (state) {
      SyncInitial() => const Text('Chưa kiểm tra trạng thái.'),
      SyncInProgress(:final message) => Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      SyncUnavailable(:final message) => Text(message),
      SyncSetupRequired() => const Text(
        'Chưa có cloud vault. Recovery key sẽ chỉ hiển thị một lần.',
      ),
      SyncRecoveryRequired(:final remoteUpdatedAt) => Text(
        'Thiết bị này cần recovery key. Snapshot: ${_format(remoteUpdatedAt)}.',
      ),
      SyncRecoveryKeyReady() => const Text('Đang chờ xác nhận recovery key.'),
      SyncRecoveryKeyRotationReady() => const Text(
        'Đang chờ xác nhận recovery key mới.',
      ),
      SyncVaultKeyRotationReady() => const Text(
        'Đang chờ xác nhận vault key và recovery key mới.',
      ),
      SyncReady(:final isEnabled, :final revision, :final updatedAt) => Text(
        '${isEnabled ? 'Đang bật' : 'Đang tắt'} · revision $revision · ${_format(updatedAt)}',
      ),
      SyncConflict(:final remoteRevision) => Text(
        'Phát hiện thay đổi đồng thời ở cloud revision $remoteRevision. Cần chọn dữ liệu giữ lại.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      SyncSuccess(:final revision, :final completedAt) => Text(
        'Đã đồng bộ revision $revision · ${_format(completedAt)}',
      ),
      SyncFailure(:final message) => Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    };
  }

  Widget _actions(BuildContext context, SyncState state) {
    if (state is SyncInProgress ||
        state is SyncRecoveryKeyReady ||
        state is SyncRecoveryKeyRotationReady ||
        state is SyncVaultKeyRotationReady) {
      return const SizedBox.shrink();
    }
    if (state is SyncSetupRequired) {
      return FilledButton.icon(
        onPressed: () =>
            context.read<SyncBloc>().add(const BeginEncryptedSyncSetup()),
        icon: const Icon(Icons.vpn_key),
        label: const Text('Thiết lập recovery key'),
      );
    }
    if (state is SyncRecoveryRequired) {
      return FilledButton.icon(
        onPressed: () => _showRecoveryImportDialog(context),
        icon: const Icon(Icons.key),
        label: const Text('Nhập recovery key'),
      );
    }
    if (state is SyncConflict) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => _confirmUseCloud(context),
            child: const Text('Dùng bản cloud'),
          ),
          FilledButton.tonal(
            onPressed: () => _confirmKeepLocal(context),
            child: const Text('Giữ bản local'),
          ),
        ],
      );
    }
    if (state is SyncFailure) {
      return OutlinedButton.icon(
        onPressed: () => context.read<SyncBloc>().add(const CheckSyncStatus()),
        icon: const Icon(Icons.refresh),
        label: const Text('Kiểm tra lại'),
      );
    }
    final canSync = switch (state) {
      SyncReady(:final isEnabled) => isEnabled,
      SyncSuccess() => true,
      _ => false,
    };
    final canRotate = state is SyncReady || state is SyncSuccess;
    if (!canSync && !canRotate) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canSync)
          FilledButton.icon(
            onPressed: () =>
                context.read<SyncBloc>().add(const SyncNowRequested()),
            icon: const Icon(Icons.sync),
            label: const Text('Đồng bộ ngay'),
          ),
        if (canRotate)
          OutlinedButton.icon(
            onPressed: () =>
                context.read<SyncBloc>().add(const BeginRecoveryKeyRotation()),
            icon: const Icon(Icons.key),
            label: const Text('Đổi recovery key'),
          ),
        if (canRotate)
          OutlinedButton.icon(
            onPressed: () =>
                context.read<SyncBloc>().add(const BeginVaultKeyRotation()),
            icon: const Icon(Icons.security_update_warning),
            label: const Text('Xoay vault key'),
          ),
      ],
    );
  }

  Future<void> _showRecoveryKeyDialog(
    BuildContext context,
    String recoveryCode, {
    required _RecoveryKeyOperation operation,
  }) async {
    var confirmedSaved = false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            operation == _RecoveryKeyOperation.setup
                ? 'Lưu recovery key'
                : 'Lưu recovery key mới',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (operation) {
                  _RecoveryKeyOperation.setup =>
                    'Key này không được gửi lên server. Mất mọi thiết bị và key sẽ không thể khôi phục cloud vault.',
                  _RecoveryKeyOperation.recoveryKeyRotation =>
                    'Recovery key cũ không thể mở snapshot hiện tại sau khi hoàn tất. Thiết bị đã giữ vault key vẫn tiếp tục hoạt động.',
                  _RecoveryKeyOperation.vaultKeyRotation =>
                    'Cả vault key và recovery key sẽ đổi. Thiết bị khác chỉ giữ vault key cũ sẽ không đọc được snapshot mới và phải nhập recovery key mới. Thao tác không đăng xuất session Supabase khác và không xóa backup lịch sử.',
                }),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      recoveryCode,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmedSaved,
                  onChanged: (value) =>
                      setDialogState(() => confirmedSaved = value ?? false),
                  title: const Text(
                    'Tôi đã lưu key vào password manager hoặc nơi an toàn.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: confirmedSaved
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(switch (operation) {
                _RecoveryKeyOperation.setup => 'Bật encrypted sync',
                _RecoveryKeyOperation.recoveryKeyRotation =>
                  'Xoay recovery key',
                _RecoveryKeyOperation.vaultKeyRotation => 'Xoay vault key',
              }),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (accepted == true) {
      context.read<SyncBloc>().add(switch (operation) {
        _RecoveryKeyOperation.setup => const ConfirmRecoveryKeySaved(),
        _RecoveryKeyOperation.recoveryKeyRotation =>
          const ConfirmRecoveryKeyRotation(),
        _RecoveryKeyOperation.vaultKeyRotation =>
          const ConfirmVaultKeyRotation(),
      });
    } else {
      context.read<SyncBloc>().add(const CancelSensitiveSyncOperation());
    }
  }

  Future<void> _showRecoveryImportDialog(BuildContext context) async {
    final recoveryCode = await showRecoveryImportDialog(context);
    if (recoveryCode?.trim().isNotEmpty == true && context.mounted) {
      context.read<SyncBloc>().add(RecoverEncryptedSync(recoveryCode!.trim()));
    }
  }

  Future<void> _confirmUseCloud(BuildContext context) async {
    final confirmed = await _confirmResolution(
      context,
      title: 'Thay local vault bằng bản cloud?',
      message:
          'Thao tác tạo một local snapshot mới từ cloud. Snapshot local hợp lệ hiện tại vẫn có generation rollback nhưng sẽ không còn là bản active.',
      action: 'Dùng cloud',
    );
    if (confirmed && context.mounted) {
      context.read<SyncBloc>().add(const ResolveSyncConflictWithCloud());
    }
  }

  Future<void> _confirmKeepLocal(BuildContext context) async {
    final confirmed = await _confirmResolution(
      context,
      title: 'Ghi bản local lên cloud?',
      message:
          'Một encrypted revision mới sẽ thay thế snapshot cloud hiện tại. Server sẽ từ chối nếu cloud tiếp tục thay đổi trước lúc commit.',
      action: 'Giữ local',
    );
    if (confirmed && context.mounted) {
      context.read<SyncBloc>().add(const ResolveSyncConflictWithLocal());
    }
  }

  Future<bool> _confirmResolution(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  String _format(DateTime value) =>
      DateFormat.yMd().add_Hm().format(value.toLocal());
}

enum _RecoveryKeyOperation { setup, recoveryKeyRotation, vaultKeyRotation }
