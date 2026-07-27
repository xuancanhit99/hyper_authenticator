part of 'encrypted_backup_bloc.dart';

sealed class EncryptedBackupEvent extends Equatable {
  const EncryptedBackupEvent();
}

final class CreateEncryptedBackupRequested extends EncryptedBackupEvent {
  const CreateEncryptedBackupRequested(this.password);

  final String password;

  @override
  List<Object?> get props => [password.length];

  @override
  String toString() => 'CreateEncryptedBackupRequested(password: [REDACTED])';
}

final class PickEncryptedBackupRequested extends EncryptedBackupEvent {
  const PickEncryptedBackupRequested();

  @override
  List<Object?> get props => const [];
}

final class DecryptEncryptedBackupRequested extends EncryptedBackupEvent {
  const DecryptEncryptedBackupRequested(this.password);

  final String password;

  @override
  List<Object?> get props => [password.length];

  @override
  String toString() => 'DecryptEncryptedBackupRequested(password: [REDACTED])';
}

final class ConfirmEncryptedBackupRestore extends EncryptedBackupEvent {
  const ConfirmEncryptedBackupRestore(this.token);

  final String token;

  @override
  List<Object?> get props => [token];
}

final class DiscardEncryptedBackup extends EncryptedBackupEvent {
  const DiscardEncryptedBackup({this.reason});

  final String? reason;

  @override
  List<Object?> get props => [reason];
}

final class EncryptedBackupPreviewExpired extends EncryptedBackupEvent {
  const EncryptedBackupPreviewExpired(this.token);

  final String token;

  @override
  List<Object?> get props => [token];
}
