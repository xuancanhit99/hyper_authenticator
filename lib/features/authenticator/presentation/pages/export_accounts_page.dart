import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/core/widgets/responsive_content.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/sensitive_action_authenticator.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum AccountExportFormat { googleAuthenticator, otpauth }

class ExportAccountsPage extends StatefulWidget {
  const ExportAccountsPage({
    super.key,
    this.authenticator,
    this.platformSupported,
    this.sessionDuration = const Duration(seconds: 60),
    this.foregroundResumeTimeout = const Duration(seconds: 2),
    this.initialFormat = AccountExportFormat.googleAuthenticator,
  });

  final SensitiveActionAuthenticator? authenticator;
  final bool? platformSupported;
  final Duration sessionDuration;
  final Duration foregroundResumeTimeout;
  final AccountExportFormat initialFormat;

  @override
  State<ExportAccountsPage> createState() => _ExportAccountsPageState();
}

class _ExportAccountsPageState extends State<ExportAccountsPage>
    with WidgetsBindingObserver {
  late final SensitiveActionAuthenticator _authenticator;
  late final bool _platformSupported;
  late AccountExportFormat _format;
  final Set<String> _selectedIds = <String>{};
  List<_ProtectedQrExportPart>? _parts;
  Timer? _expiryTimer;
  Completer<void>? _foregroundResumeCompleter;
  int _partIndex = 0;
  int _secondsRemaining = 0;
  int _authenticationGeneration = 0;
  bool _authenticating = false;
  bool _applicationIsResumed = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authenticator = widget.authenticator ?? sl<SensitiveActionAuthenticator>();
    _format = widget.initialFormat;
    _platformSupported =
        widget.platformSupported ??
        PlatformCapabilities.supportsLocalAuthentication;
    _secondsRemaining = widget.sessionDuration.inSeconds;
    _applicationIsResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<AccountsBloc>();
      if (bloc.state is! AccountsLoaded) {
        bloc.add(LoadAccounts());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _foregroundResumeCompleter?.complete();
    _foregroundResumeCompleter = null;
    _parts = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationIsResumed = state == AppLifecycleState.resumed;
    if (_applicationIsResumed) {
      _foregroundResumeCompleter?.complete();
      _foregroundResumeCompleter = null;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_parts != null) {
        _closeExport(message: 'Đã đóng mã QR vì ứng dụng chuyển sang nền.');
      }
    }
  }

  bool _isCompatible(AuthenticatorAccount account) {
    try {
      switch (_format) {
        case AccountExportFormat.googleAuthenticator:
          GoogleAuthenticatorMigrationExporter.validateAccounts([account]);
        case AccountExportFormat.otpauth:
          TotpUriExporter.validateAccounts([account]);
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  void _setFormat(
    AccountExportFormat format,
    List<AuthenticatorAccount> accounts,
  ) {
    if (_authenticating || format == _format) return;
    setState(() {
      _format = format;
      _selectedIds.removeWhere((id) {
        final index = accounts.indexWhere((item) => item.id == id);
        return index == -1 || !_isCompatible(accounts[index]);
      });
      _statusMessage = null;
    });
  }

  void _toggleAll(List<AuthenticatorAccount> accounts) {
    final compatibleIds = accounts
        .where(_isCompatible)
        .map((account) => account.id)
        .toSet();
    setState(() {
      if (_selectedIds.containsAll(compatibleIds)) {
        _selectedIds.removeAll(compatibleIds);
      } else {
        _selectedIds.addAll(compatibleIds);
      }
      _statusMessage = null;
    });
  }

  Future<void> _startExport(List<AuthenticatorAccount> accounts) async {
    if (_authenticating || !_platformSupported) return;
    final selectedIds = Set<String>.of(_selectedIds);
    final selected = accounts
        .where((account) => selectedIds.contains(account.id))
        .toList(growable: false);
    final format = _format;
    try {
      switch (format) {
        case AccountExportFormat.googleAuthenticator:
          GoogleAuthenticatorMigrationExporter.validateAccounts(selected);
        case AccountExportFormat.otpauth:
          TotpUriExporter.validateAccounts(selected);
      }
    } on FormatException {
      setState(() {
        _statusMessage =
            'Không thể tạo mã QR cho lựa chọn này. Hãy kiểm tra lại các mã.';
      });
      return;
    }

    final generation = ++_authenticationGeneration;
    setState(() {
      _authenticating = true;
      _statusMessage = null;
    });
    final result = await _authenticator.authenticateForExport();
    if (!mounted || generation != _authenticationGeneration) return;

    if (result != SensitiveActionAuthenticationResult.success) {
      setState(() {
        _authenticating = false;
        _statusMessage = switch (result) {
          SensitiveActionAuthenticationResult.canceled =>
            'Đã hủy xác thực. Chưa tạo mã QR.',
          SensitiveActionAuthenticationResult.unavailable =>
            'Hãy thiết lập khóa màn hình trên thiết bị rồi thử lại.',
          SensitiveActionAuthenticationResult.failed =>
            'Không thể xác thực an toàn. Hãy thử lại.',
          SensitiveActionAuthenticationResult.success => null,
        };
      });
      return;
    }

    final resumed = await _waitForForegroundAfterAuthentication(generation);
    if (!mounted || generation != _authenticationGeneration) return;
    if (!resumed) {
      setState(() {
        _authenticating = false;
        _statusMessage = 'Ứng dụng đang ở nền. Chưa tạo mã QR.';
      });
      return;
    }

    final currentState = context.read<AccountsBloc>().state;
    if (currentState is! AccountsLoaded) {
      setState(() {
        _authenticating = false;
        _statusMessage = 'Danh sách mã vừa thay đổi. Hãy chọn lại.';
      });
      return;
    }
    final currentAccounts = currentState.accounts
        .where((account) => selectedIds.contains(account.id))
        .toList(growable: false);
    if (currentAccounts.length != selectedIds.length) {
      setState(() {
        _authenticating = false;
        _statusMessage = 'Danh sách mã vừa thay đổi. Hãy chọn lại.';
      });
      return;
    }

    try {
      final parts = _exportParts(format, currentAccounts);
      if (!mounted || generation != _authenticationGeneration) return;
      setState(() {
        _authenticating = false;
        _parts = parts;
        _partIndex = 0;
        _secondsRemaining = widget.sessionDuration.inSeconds;
        _statusMessage = null;
      });
      _startExpiryTimer();
    } on FormatException {
      setState(() {
        _authenticating = false;
        _statusMessage =
            'Không thể tạo mã QR cho lựa chọn này. Hãy kiểm tra lại các mã.';
      });
    }
  }

  List<_ProtectedQrExportPart> _exportParts(
    AccountExportFormat format,
    List<AuthenticatorAccount> accounts,
  ) {
    return switch (format) {
      AccountExportFormat.googleAuthenticator => [
        for (final part in GoogleAuthenticatorMigrationExporter.export(
          accounts,
        ))
          _ProtectedQrExportPart(
            format: format,
            uri: part.uri,
            index: part.index,
            total: part.total,
          ),
      ],
      AccountExportFormat.otpauth => [
        for (final part in TotpUriExporter.export(accounts))
          _ProtectedQrExportPart(
            format: format,
            uri: part.uri,
            index: part.index,
            total: part.total,
          ),
      ],
    };
  }

  Future<bool> _waitForForegroundAfterAuthentication(int generation) async {
    if (_applicationIsResumed) return true;

    final completer = Completer<void>();
    _foregroundResumeCompleter = completer;
    try {
      await completer.future.timeout(widget.foregroundResumeTimeout);
    } on TimeoutException {
      return false;
    } finally {
      if (identical(_foregroundResumeCompleter, completer)) {
        _foregroundResumeCompleter = null;
      }
    }
    return mounted &&
        generation == _authenticationGeneration &&
        _applicationIsResumed;
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _parts == null) return;
      if (_secondsRemaining <= 1) {
        _closeExport(message: 'Mã QR đã hết hạn và được xóa khỏi màn hình.');
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  void _closeExport({String? message}) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _authenticationGeneration++;
    if (!mounted) return;
    setState(() {
      _parts = null;
      _partIndex = 0;
      _secondsRemaining = widget.sessionDuration.inSeconds;
      _authenticating = false;
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xuất mã xác thực')),
      body: SafeArea(
        child: MaxWidthContent(
          maxWidth: 760,
          child: BlocBuilder<AccountsBloc, AccountsState>(
            builder: (context, state) {
              if (_parts case final parts?) {
                return _buildExportSession(context, parts);
              }
              if (state is AccountsLoading || state is AccountsInitial) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is AccountsError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Không thể tải danh sách mã.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (state case AccountsLoaded(:final accounts)) {
                _selectedIds.removeWhere(
                  (id) => !accounts.any((account) => account.id == id),
                );
                return _buildSelection(context, accounts);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSelection(
    BuildContext context,
    List<AuthenticatorAccount> accounts,
  ) {
    if (!_platformSupported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phonelink_lock_outlined, size: 48),
              SizedBox(height: 16),
              Text(
                'Thiết bị này chưa hỗ trợ xác thực để xuất mã.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final compatibleAccounts = accounts.where(_isCompatible).toList();
    final allSelected =
        compatibleAccounts.isNotEmpty &&
        compatibleAccounts.every(
          (account) => _selectedIds.contains(account.id),
        );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded),
                    SizedBox(height: 8),
                    Text(
                      'Mã QR chứa khóa thiết lập',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Bất kỳ ai quét được đều có thể tạo mã của bạn. Không '
                      'chụp, chia sẻ hoặc gửi mã QR cho người khác.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dùng với',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          key: const Key('export-format-google'),
                          label: const Text('Google Authenticator'),
                          selected:
                              _format ==
                              AccountExportFormat.googleAuthenticator,
                          onSelected: _authenticating
                              ? null
                              : (_) => _setFormat(
                                  AccountExportFormat.googleAuthenticator,
                                  accounts,
                                ),
                        ),
                        ChoiceChip(
                          key: const Key('export-format-otpauth'),
                          label: const Text('Ứng dụng khác'),
                          selected: _format == AccountExportFormat.otpauth,
                          onSelected: _authenticating
                              ? null
                              : (_) => _setFormat(
                                  AccountExportFormat.otpauth,
                                  accounts,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _format == AccountExportFormat.googleAuthenticator
                          ? 'Gộp nhiều mã vào một lần chuyển.'
                          : 'Tạo một mã QR riêng cho từng mã xác thực.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_statusMessage case final message?)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            sliver: SliverToBoxAdapter(
              child: Semantics(
                liveRegion: true,
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: compatibleAccounts.isEmpty || _authenticating
                      ? null
                      : () => _toggleAll(accounts),
                  child: Text(
                    allSelected ? 'Bỏ chọn tất cả' : 'Chọn tất cả',
                    textAlign: TextAlign.center,
                  ),
                ),
                Text('${_selectedIds.length} mã đã chọn'),
              ],
            ),
          ),
        ),
        if (accounts.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Chưa có mã để xuất.')),
            ),
          )
        else
          SliverList.builder(
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index];
              final compatible = _isCompatible(account);
              return CheckboxListTile(
                key: Key('export-account-${account.id}'),
                value: _selectedIds.contains(account.id),
                onChanged: compatible && !_authenticating
                    ? (selected) {
                        setState(() {
                          if (selected ?? false) {
                            _selectedIds.add(account.id);
                          } else {
                            _selectedIds.remove(account.id);
                          }
                          _statusMessage = null;
                        });
                      }
                    : null,
                title: Text(account.issuer),
                subtitle: Text(
                  compatible
                      ? account.accountName
                      : '${account.accountName} · '
                            '${_format == AccountExportFormat.googleAuthenticator ? 'Chỉ hỗ trợ mã 30 giây, gồm 6 hoặc 8 chữ số.' : 'Không thể tạo QR cho mã này.'}',
                ),
              );
            },
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('authenticate-and-export'),
                onPressed: _selectedIds.isEmpty || _authenticating
                    ? null
                    : () => _startExport(accounts),
                child: _authenticating
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Tạo mã QR'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExportSession(
    BuildContext context,
    List<_ProtectedQrExportPart> parts,
  ) {
    final part = parts[_partIndex];
    final qrSize = (MediaQuery.sizeOf(context).width - 48)
        .clamp(160.0, 280.0)
        .toDouble();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                'QR tự đóng sau $_secondsRemaining giây',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Text(switch (part.format) {
              AccountExportFormat.googleAuthenticator =>
                parts.length == 1
                    ? 'Quét QR này trong Google Authenticator'
                    : 'Quét lần lượt đủ ${parts.length} mã QR',
              AccountExportFormat.otpauth =>
                parts.length == 1
                    ? 'Quét QR này bằng ứng dụng xác thực khác'
                    : 'Quét lần lượt ${parts.length} mã QR',
            }, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Semantics(
              label:
                  '${part.format == AccountExportFormat.googleAuthenticator ? 'Mã QR chuyển sang Google Authenticator, phần' : 'Mã QR chuyển sang ứng dụng khác, mã'} '
                  '${part.index + 1} trên ${part.total}',
              image: true,
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    key: ValueKey(
                      'export-qr-${part.format.name}-${part.index}',
                    ),
                    data: part.uri,
                    size: qrSize,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    semanticsLabel: 'Mã QR chuyển mã xác thực',
                    errorStateBuilder: (_, _) => SizedBox(
                      width: qrSize,
                      height: qrSize,
                      child: const Center(child: Text('Không thể tạo mã QR.')),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${part.format == AccountExportFormat.googleAuthenticator ? 'Phần' : 'Tài khoản'} '
              '${part.index + 1}/${part.total}',
            ),
            if (parts.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'QR trước',
                    onPressed: _partIndex == 0
                        ? null
                        : () => setState(() => _partIndex--),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    tooltip: 'QR tiếp theo',
                    onPressed: _partIndex == parts.length - 1
                        ? null
                        : () => setState(() => _partIndex++),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _closeExport(message: 'Đã đóng mã QR.'),
              icon: const Icon(Icons.close),
              label: const Text('Đóng mã QR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtectedQrExportPart {
  const _ProtectedQrExportPart({
    required this.format,
    required this.uri,
    required this.index,
    required this.total,
  });

  final AccountExportFormat format;
  final String uri;
  final int index;
  final int total;

  @override
  String toString() =>
      '_ProtectedQrExportPart('
      'format: $format, uri: [REDACTED], index: $index, total: $total)';
}
