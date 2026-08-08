import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

/// Một record cloud thuộc user hiện hành.
///
/// [account] chỉ có giá trị với record đang hoạt động. Tombstone không mang
/// plaintext credential trở lại client.
class CloudAccountRecord extends Equatable {
  const CloudAccountRecord({
    required this.accountId,
    required this.revision,
    required this.updatedAt,
    required this.deletedAt,
    required this.account,
  });

  final String accountId;
  final int revision;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final AuthenticatorAccount? account;

  bool get isDeleted => deletedAt != null;

  @override
  List<Object?> get props => [
    accountId,
    revision,
    updatedAt,
    deletedAt,
    account,
  ];

  @override
  String toString() =>
      'CloudAccountRecord(accountId: [REDACTED], revision: $revision, '
      'isDeleted: $isDeleted, account: [REDACTED])';
}
