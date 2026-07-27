part of 'encrypted_backup_bloc.dart';

sealed class EncryptedBackupState extends Equatable {
  const EncryptedBackupState();
}

final class EncryptedBackupInitial extends EncryptedBackupState {
  const EncryptedBackupInitial();

  @override
  List<Object?> get props => const [];
}

final class EncryptedBackupBusy extends EncryptedBackupState {
  const EncryptedBackupBusy(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class EncryptedBackupPasswordRequired extends EncryptedBackupState {
  const EncryptedBackupPasswordRequired();

  @override
  List<Object?> get props => const [];
}

class EncryptedBackupAccountPreview extends Equatable {
  const EncryptedBackupAccountPreview({
    required this.issuer,
    required this.accountName,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  factory EncryptedBackupAccountPreview.fromAccount(
    AuthenticatorAccount account,
  ) => EncryptedBackupAccountPreview(
    issuer: account.issuer,
    accountName: account.accountName,
    algorithm: account.algorithm,
    digits: account.digits,
    period: account.period,
  );

  final String issuer;
  final String accountName;
  final String algorithm;
  final int digits;
  final int period;

  @override
  List<Object?> get props => [issuer, accountName, algorithm, digits, period];

  @override
  String toString() => 'EncryptedBackupAccountPreview([REDACTED])';
}

final class EncryptedBackupRestorePreview extends EncryptedBackupState {
  EncryptedBackupRestorePreview({
    required this.token,
    required this.createdAt,
    required this.currentAccountCount,
    required List<EncryptedBackupAccountPreview> accounts,
    required this.expiresAt,
  }) : accounts = List<EncryptedBackupAccountPreview>.unmodifiable(accounts);

  final String token;
  final DateTime createdAt;
  final int currentAccountCount;
  final List<EncryptedBackupAccountPreview> accounts;
  final DateTime expiresAt;

  @override
  List<Object?> get props => [
    token,
    createdAt,
    currentAccountCount,
    accounts,
    expiresAt,
  ];

  @override
  String toString() =>
      'EncryptedBackupRestorePreview(token: $token, createdAt: $createdAt, '
      'currentAccountCount: $currentAccountCount, '
      'accounts: [${accounts.length} REDACTED], expiresAt: $expiresAt)';
}

final class EncryptedBackupSuccess extends EncryptedBackupState {
  const EncryptedBackupSuccess({required this.message, required this.restored});

  final String message;
  final bool restored;

  @override
  List<Object?> get props => [message, restored];
}

final class EncryptedBackupFailure extends EncryptedBackupState {
  const EncryptedBackupFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class EncryptedBackupCancelled extends EncryptedBackupState {
  const EncryptedBackupCancelled(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
