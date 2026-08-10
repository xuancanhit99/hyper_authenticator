import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';
import 'package:hyper_authenticator/core/widgets/responsive_content.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/appearance_style_picker.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/cloud_account_action_tile.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/product_info_tile.dart';
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
        BlocProvider.value(value: sl<SyncBloc>()),
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
    final cloudConfigured = sl<AppConfig>().cloudEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text(AppCopy.settings)),
      body: BlocConsumer<SettingsBloc, SettingsState>(
        listenWhen: (previous, current) =>
            previous is SettingsLoaded && current is SettingsError,
        listener: (context, state) {
          if (state case SettingsError(:final message)) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          if (state is SettingsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is SettingsError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings_backup_restore, size: 40),
                    const SizedBox(height: 12),
                    Text(state.message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          context.read<SettingsBloc>().add(LoadSettings()),
                      icon: const Icon(Icons.refresh),
                      label: const Text(AppCopy.retry),
                    ),
                  ],
                ),
              ),
            );
          }
          final loaded = state is SettingsLoaded ? state : null;
          return MaxWidthContent(
            maxWidth: 760,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionLabel('Tài khoản & đồng bộ'),
                Card(
                  child: _AccountSyncSection(
                    currentUser: currentUser,
                    cloudConfigured: cloudConfigured,
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Bảo mật'),
                Card(
                  child: loaded?.canCheckBiometrics == true
                      ? SwitchListTile(
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
                      : const ListTile(
                          leading: Icon(Icons.fingerprint),
                          title: Text('Khóa bằng sinh trắc học'),
                          subtitle: Text(
                            'Thiết bị này không hỗ trợ khóa ứng dụng.',
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Hiển thị'),
                const Card(child: AppearanceStylePicker()),
                const SizedBox(height: 20),
                const _SectionLabel('Thông tin'),
                const Card(child: ProductInfoTile()),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AccountSyncSection extends StatelessWidget {
  const _AccountSyncSection({
    required this.currentUser,
    required this.cloudConfigured,
  });

  final UserEntity? currentUser;
  final bool cloudConfigured;

  @override
  Widget build(BuildContext context) {
    if (!cloudConfigured) {
      return const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Chỉ lưu trên thiết bị'),
        subtitle: Text('Đồng bộ chưa khả dụng trong phiên bản này.'),
      );
    }

    if (currentUser == null) {
      return const CloudAccountActionTile(currentUser: null);
    }

    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UserTile(currentUser!),
            _divider(context),
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Đồng bộ'),
              subtitle: Semantics(
                container: true,
                liveRegion: state is SyncInProgress || state is SyncFailure,
                child: _status(context, state),
              ),
            ),
            if (state is SyncFailure)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(56, 0, 24, 8),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.read<SyncBloc>().add(const SyncNowRequested()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử đồng bộ lại'),
                ),
              ),
            _divider(context),
            CloudAccountActionTile(currentUser: currentUser),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
    height: 1,
    indent: 56,
    endIndent: 24,
    color: Theme.of(context).colorScheme.outlineVariant,
  );

  Widget _status(BuildContext context, SyncState state) {
    return switch (state) {
      SyncInitial() => const Text('Đang chuẩn bị đồng bộ…'),
      SyncSignedOut() => const Text('Đang kết nối…'),
      SyncInProgress() => const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Expanded(child: Text('Đang đồng bộ…')),
        ],
      ),
      SyncReady(:final completedAt) => Text(
        'Đã đồng bộ tự động · ${_format(completedAt)}',
      ),
      SyncFailure(:final message) => Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    };
  }

  String _format(DateTime value) =>
      DateFormat.yMd().add_Hm().format(value.toLocal());
}

class _UserTile extends StatelessWidget {
  const _UserTile(this.user);

  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    final name = user.name?.trim();
    final email = user.email?.trim();
    final label = name?.isNotEmpty == true
        ? name!
        : email?.isNotEmpty == true
        ? email!
        : 'Tài khoản đồng bộ';

    return ListTile(
      leading: CircleAvatar(child: Text(label.characters.first.toUpperCase())),
      title: Text(label),
      subtitle: email?.isNotEmpty == true ? Text(email!) : null,
    );
  }
}
