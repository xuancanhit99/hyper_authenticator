import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_exporter.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/sensitive_action_authenticator.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ExportAccountsPage extends StatefulWidget {
  const ExportAccountsPage({
    super.key,
    this.authenticator,
    this.platformSupported,
    this.sessionDuration = const Duration(seconds: 60),
    this.foregroundResumeTimeout = const Duration(seconds: 2),
  });

  final SensitiveActionAuthenticator? authenticator;
  final bool? platformSupported;
  final Duration sessionDuration;
  final Duration foregroundResumeTimeout;

  @override
  State<ExportAccountsPage> createState() => _ExportAccountsPageState();
}

class _ExportAccountsPageState extends State<ExportAccountsPage>
    with WidgetsBindingObserver {
  late final SensitiveActionAuthenticator _authenticator;
  late final bool _platformSupported;
  final Set<String> _selectedIds = <String>{};
  List<GoogleAuthenticatorMigrationExportPart>? _parts;
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
        _closeExport(
          message: 'Phiên export đã đóng vì ứng dụng không còn ở foreground.',
        );
      }
    }
  }

  bool _isCompatible(AuthenticatorAccount account) =>
      account.period == 30 && (account.digits == 6 || account.digits == 8);

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
    try {
      GoogleAuthenticatorMigrationExporter.validateAccounts(selected);
    } on FormatException catch (error) {
      setState(() => _statusMessage = error.message.toString());
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
            'Bạn đã hủy xác thực; chưa có QR nào được tạo.',
          SensitiveActionAuthenticationResult.unavailable =>
            'Thiết bị chưa cấu hình phương thức xác thực hệ điều hành.',
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
        _statusMessage =
            'Ứng dụng không còn ở foreground; chưa có QR nào được tạo.';
      });
      return;
    }

    try {
      final currentState = context.read<AccountsBloc>().state;
      if (currentState is! AccountsLoaded) {
        throw const FormatException(
          'Danh sách tài khoản vừa thay đổi. Hãy tải lại và chọn lại.',
        );
      }
      final currentAccounts = currentState.accounts
          .where((account) => selectedIds.contains(account.id))
          .toList(growable: false);
      if (currentAccounts.length != selectedIds.length) {
        throw const FormatException(
          'Danh sách tài khoản vừa thay đổi. Hãy chọn lại trước khi export.',
        );
      }
      final parts = GoogleAuthenticatorMigrationExporter.export(
        currentAccounts,
      );
      if (!mounted || generation != _authenticationGeneration) return;
      setState(() {
        _authenticating = false;
        _parts = parts;
        _partIndex = 0;
        _secondsRemaining = widget.sessionDuration.inSeconds;
        _statusMessage = null;
      });
      _startExpiryTimer();
    } on FormatException catch (error) {
      setState(() {
        _authenticating = false;
        _statusMessage = error.message.toString();
      });
    }
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
        _closeExport(
          message: 'QR export đã hết hạn và được xóa khỏi màn hình.',
        );
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
      appBar: AppBar(title: const Text('Xuất tài khoản')),
      body: SafeArea(
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
                    'Không thể tải tài khoản để export.',
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
                'Export chưa khả dụng trên nền tảng này vì chưa có ranh giới '
                'xác thực hệ điều hành an toàn.',
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
                      'QR export chứa khóa bí mật TOTP',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Người quét được QR có thể tạo mã xác thực của bạn. '
                      'Không chụp màn hình, chia sẻ màn hình hoặc gửi QR qua chat.',
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
                Text('${_selectedIds.length} đã chọn'),
              ],
            ),
          ),
        ),
        if (accounts.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Chưa có tài khoản để export.')),
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
                      : '${account.accountName} · Không tương thích: '
                            'Google transfer yêu cầu period 30 giây và '
                            '6 hoặc 8 chữ số.',
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
                    : Text(
                        'Xác thực và tạo QR '
                        '(${widget.sessionDuration.inSeconds} giây)',
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExportSession(
    BuildContext context,
    List<GoogleAuthenticatorMigrationExportPart> parts,
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
            Text(
              parts.length == 1
                  ? 'Quét QR này trong Google Authenticator'
                  : 'Quét lần lượt đủ ${parts.length} QR trong cùng một phiên',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Semantics(
              label:
                  'Mã QR export Google Authenticator, phần '
                  '${part.index + 1} trên ${part.total}',
              image: true,
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    key: ValueKey('export-qr-${part.index}'),
                    data: part.uri,
                    size: qrSize,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    semanticsLabel: 'Mã QR export được bảo vệ',
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
            Text('Phần ${part.index + 1}/${part.total}'),
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
              onPressed: () =>
                  _closeExport(message: 'QR export đã được đóng theo yêu cầu.'),
              icon: const Icon(Icons.close),
              label: const Text('Đóng QR ngay'),
            ),
          ],
        ),
      ),
    );
  }
}
