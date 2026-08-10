import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/localization/app_copy.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';

enum TotpImportSource {
  googleAuthenticator('từ Google Authenticator'),
  otpauth('trong mã QR');

  const TotpImportSource(this.originCopy);

  final String originCopy;
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
      title: const Text('Kiểm tra mã sẽ nhập'),
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
                    'Đã tìm thấy ${accounts.length} mã ${source.originCopy}.',
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
                              'Khóa thiết lập được giữ ẩn. Chỉ nhập những mã '
                              'bạn tin cậy.',
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
          child: const Text(AppCopy.cancel),
        ),
        FilledButton.icon(
          key: confirmButtonKey,
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.download_done_outlined),
          label: Text('Nhập ${accounts.length} mã'),
        ),
      ],
    );
  }
}
