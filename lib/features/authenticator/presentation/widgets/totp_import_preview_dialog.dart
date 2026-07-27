import 'package:flutter/material.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';

enum TotpImportSource {
  googleAuthenticator('Google Authenticator'),
  otpauth('Chuẩn otpauth');

  const TotpImportSource(this.label);

  final String label;
}

class TotpImportPreviewDialog extends StatelessWidget {
  const TotpImportPreviewDialog({
    required this.accounts,
    required this.source,
    super.key,
  });

  static const cancelButtonKey = ValueKey<String>('totp-import-preview-cancel');
  static const confirmButtonKey = ValueKey<String>(
    'totp-import-preview-confirm',
  );
  static const accountListKey = ValueKey<String>(
    'totp-import-preview-accounts',
  );

  final List<ParsedTotpAccount> accounts;
  final TotpImportSource source;

  static Future<bool> show(
    BuildContext context,
    List<ParsedTotpAccount> accounts,
    TotpImportSource source,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              TotpImportPreviewDialog(accounts: accounts, source: source),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final contentHeight = (MediaQuery.sizeOf(context).height * 0.38)
        .clamp(200.0, 480.0)
        .toDouble();
    return AlertDialog(
      title: const Text('Import tài khoản'),
      content: SizedBox(
        width: 480,
        height: contentHeight,
        child: CustomScrollView(
          key: accountListKey,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${source.label}: đã đọc ${accounts.length} tài '
                    'khoản. Kiểm tra danh sách trước khi lưu vào thiết bị này.',
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.security_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'QR export chứa credential TOTP. Secret không '
                              'được hiển thị và chỉ được ghi sau khi bạn xác '
                              'nhận.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: accounts.length,
              itemBuilder: (context, index) {
                final account = accounts[index];
                return Column(
                  children: [
                    MergeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AccountAvatar(issuer: account.issuer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.issuer,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(account.accountName),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${account.algorithm} · '
                                    '${account.digits} chữ số · '
                                    '${account.period} giây',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (index < accounts.length - 1) const Divider(height: 1),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: cancelButtonKey,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: confirmButtonKey,
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.download_done_outlined),
          label: const Text('Import'),
        ),
      ],
    );
  }
}
