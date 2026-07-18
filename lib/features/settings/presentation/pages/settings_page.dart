import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/session_security_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/encrypted_sync_unavailable_tile.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/authentication_session_tile.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/recovery_import_dialog.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/recovery_key_confirmation_dialog.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/sync_conflict_resolution_dialog.dart';
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
        BlocProvider(create: (_) => sl<SessionSecurityBloc>()),
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

    return BlocListener<SessionSecurityBloc, SessionSecurityState>(
      listener: (context, state) {
        final message = switch (state) {
          SessionSecuritySuccess() =>
            'Đã đăng xuất tất cả phiên khác. Thiết bị này vẫn đăng nhập.',
          SessionSecurityFailure(:final message) => message,
          _ => null,
        };
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      },
      child: Scaffold(
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
                      if (loaded?.canCheckBiometrics == true)
                        SwitchListTile(
                          secondary: const Icon(Icons.fingerprint),
                          title: const Text('Khóa bằng sinh trắc học'),
                          subtitle: const Text(
                            'Dùng Face ID, vân tay hoặc mã khóa thiết bị.',
                          ),
                          value: loaded!.isBiometricEnabled,
                          onChanged: (enabled) => context
                              .read<SettingsBloc>()
                              .add(ToggleBiometric(isEnabled: enabled)),
                        )
                      else
                        const ListTile(
                          leading: Icon(Icons.fingerprint),
                          title: Text('Khóa bằng sinh trắc học'),
                          subtitle: Text(
                            'Thiết bị hoặc platform không hỗ trợ.',
                          ),
                        ),
                      const Divider(height: 1),
                      _EncryptedSyncSection(
                        currentUser: currentUser,
                        isSupported: encryptedSyncSupported,
                      ),
                      if (currentUser != null || encryptedSyncSupported) ...[
                        const Divider(height: 1),
                        BlocBuilder<SessionSecurityBloc, SessionSecurityState>(
                          builder: (context, sessionSecurityState) =>
                              AuthenticationSessionTile(
                                currentUser: currentUser,
                                sessionSecurityState: sessionSecurityState,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
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
            operation: RecoveryKeyOperation.setup,
          );
        } else if (state is SyncRecoveryKeyRotationReady) {
          await _showRecoveryKeyDialog(
            context,
            state.recoveryCode,
            operation: RecoveryKeyOperation.recoveryKeyRotation,
          );
        } else if (state is SyncVaultKeyRotationReady) {
          await _showRecoveryKeyDialog(
            context,
            state.recoveryCode,
            operation: RecoveryKeyOperation.vaultKeyRotation,
          );
        } else if (state is SyncSuccess) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Đồng bộ mã hóa hoàn tất ở revision ${state.revision}.',
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
            _syncTile(context, state),
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

  Widget _syncTile(BuildContext context, SyncState state) {
    final subtitle = Semantics(
      container: true,
      liveRegion:
          state is SyncInProgress ||
          state is SyncConflict ||
          state is SyncSuccess ||
          state is SyncFailure,
      child: _statusText(context, state),
    );
    if (state case SyncReady(:final isEnabled)) {
      return SwitchListTile(
        secondary: const Icon(Icons.enhanced_encryption),
        title: const Text('Đồng bộ cloud mã hóa đầu cuối'),
        subtitle: subtitle,
        value: isEnabled,
        onChanged: (enabled) =>
            context.read<SyncBloc>().add(SetEncryptedSyncEnabled(enabled)),
      );
    }
    return ListTile(
      leading: const Icon(Icons.enhanced_encryption),
      title: const Text('Đồng bộ cloud mã hóa đầu cuối'),
      subtitle: subtitle,
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
    required RecoveryKeyOperation operation,
  }) async {
    final accepted = await showRecoveryKeyConfirmationDialog(
      context,
      recoveryCode: recoveryCode,
      operation: operation,
    );
    if (!context.mounted) return;
    if (accepted == true) {
      context.read<SyncBloc>().add(switch (operation) {
        RecoveryKeyOperation.setup => const ConfirmRecoveryKeySaved(),
        RecoveryKeyOperation.recoveryKeyRotation =>
          const ConfirmRecoveryKeyRotation(),
        RecoveryKeyOperation.vaultKeyRotation =>
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
  }) => showSyncConflictResolutionDialog(
    context,
    title: title,
    message: message,
    action: action,
  );

  String _format(DateTime value) =>
      DateFormat.yMd().add_Hm().format(value.toLocal());
}
