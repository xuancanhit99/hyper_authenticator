import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart';

class AccountCodeTile extends StatelessWidget {
  const AccountCodeTile({
    super.key,
    required this.account,
    required this.displayCode,
    required this.timeWindow,
    required this.onEdit,
    required this.onDelete,
  });

  final AuthenticatorAccount account;
  final String displayCode;
  final TotpTimeWindow timeWindow;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final rawCode = displayCode.replaceAll(' ', '');
    final canCopy = RegExp(r'^\d{6,8}$').hasMatch(rawCode);
    final semanticValue = canCopy
        ? 'Mã ${rawCode.split('').join(' ')}, còn ${timeWindow.secondsRemaining} giây'
        : 'Đang tạo mã';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            label:
                'Sao chép mã TOTP của ${account.issuer}, ${account.accountName}',
            value: semanticValue,
            button: true,
            enabled: canCopy,
            excludeSemantics: true,
            child: InkWell(
              onTap: canCopy ? () => _copyCode(context, rawCode) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: _AccountCodeContent(
                  account: account,
                  displayCode: displayCode,
                  timeWindow: timeWindow,
                ),
              ),
            ),
          ),
        ),
        PopupMenuButton<_AccountAction>(
          key: Key('account-actions-${account.id}'),
          tooltip: 'Thao tác với ${account.issuer}',
          onSelected: (action) => switch (action) {
            _AccountAction.edit => onEdit(),
            _AccountAction.delete => onDelete(),
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _AccountAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Sửa'),
              ),
            ),
            PopupMenuItem(
              value: _AccountAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Xóa'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _copyCode(BuildContext context, String rawCode) {
    Clipboard.setData(ClipboardData(text: rawCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép mã TOTP.'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

enum _AccountAction { edit, delete }

class _AccountCodeContent extends StatelessWidget {
  const _AccountCodeContent({
    required this.account,
    required this.displayCode,
    required this.timeWindow,
  });

  final AuthenticatorAccount account;
  final String displayCode;
  final TotpTimeWindow timeWindow;

  @override
  Widget build(BuildContext context) {
    final identity = _AccountIdentity(account: account);
    final codeAndCountdown = _CodeAndCountdown(
      displayCode: displayCode,
      timeWindow: timeWindow,
      periodSeconds: account.period,
    );
    final useStackedLayout = MediaQuery.textScalerOf(context).scale(21) > 28;

    if (useStackedLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AccountAvatar(issuer: account.issuer),
              const SizedBox(width: 12),
              Expanded(child: identity),
            ],
          ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: codeAndCountdown),
        ],
      );
    }
    return Row(
      children: [
        AccountAvatar(issuer: account.issuer),
        const SizedBox(width: 12),
        Expanded(child: identity),
        const SizedBox(width: 8),
        codeAndCountdown,
      ],
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({required this.account});

  final AuthenticatorAccount account;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account.issuer,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          account.accountName,
          style: Theme.of(context).textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}

class _CodeAndCountdown extends StatelessWidget {
  const _CodeAndCountdown({
    required this.displayCode,
    required this.timeWindow,
    required this.periodSeconds,
  });

  final String displayCode;
  final TotpTimeWindow timeWindow;
  final int periodSeconds;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(
          displayCode,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.3,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        CircularCountdownTimer(
          secondsRemaining: timeWindow.secondsRemaining,
          periodSeconds: periodSeconds,
          size: 18,
          backgroundColor: Colors.transparent,
          progressColor: Colors.grey,
        ),
      ],
    );
  }
}
