import 'dart:typed_data';

enum BackupFileSaveResult { saved, cancelled }

class EncryptedBackupFileSelection {
  EncryptedBackupFileSelection({
    required Uint8List bytes,
    required this.displayName,
  }) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final String displayName;

  @override
  String toString() =>
      'EncryptedBackupFileSelection(bytes: [${bytes.length} REDACTED], '
      'displayName: [REDACTED])';
}

class BackupFileIoException implements Exception {
  const BackupFileIoException(this.message);

  final String message;

  @override
  String toString() => 'BackupFileIoException([REDACTED])';
}

abstract interface class EncryptedBackupFileGateway {
  Future<EncryptedBackupFileSelection?> pickBackup();

  Future<BackupFileSaveResult> saveBackup({
    required Uint8List bytes,
    required String suggestedName,
  });
}
