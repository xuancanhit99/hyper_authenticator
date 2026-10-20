import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

/// Một record cloud thuộc user hiện hành.
///
/// [account] chỉ có giá trị với record đang hoạt động và payload hợp lệ.
/// Tombstone hoặc live record bị cô lập không mang credential tới sync logic.
class CloudAccountRecord extends Equatable {
  const CloudAccountRecord({
    required this.accountId,
    required this.revision,
    required this.updatedAt,
    required this.deletedAt,
    required this.account,
    this.isBlocked = false,
  }) : assert(!isBlocked || (account == null && deletedAt == null));

  final String accountId;
  final int revision;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final AuthenticatorAccount? account;
  final bool isBlocked;

  bool get isDeleted => deletedAt != null;

  @override
  List<Object?> get props => [
    accountId,
    revision,
    updatedAt,
    deletedAt,
    account,
    isBlocked,
  ];

  @override
  String toString() =>
      'CloudAccountRecord(accountId: [REDACTED], revision: $revision, '
      'isDeleted: $isDeleted, isBlocked: $isBlocked, account: [REDACTED])';
}
