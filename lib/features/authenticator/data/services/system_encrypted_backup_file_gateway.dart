import 'dart:typed_data';
import 'dart:ui';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:hyper_authenticator/features/authenticator/domain/repositories/encrypted_backup_file_gateway.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/encrypted_backup_file_codec.dart';
import 'package:injectable/injectable.dart';
import 'package:share_plus/share_plus.dart';

@LazySingleton(as: EncryptedBackupFileGateway)
class SystemEncryptedBackupFileGateway implements EncryptedBackupFileGateway {
  const SystemEncryptedBackupFileGateway();

  static const _typeGroup = file_selector.XTypeGroup(
    label: 'Hyper Authenticator backup',
    extensions: [EncryptedBackupFileCodec.fileExtension],
    mimeTypes: ['application/octet-stream'],
    uniformTypeIdentifiers: ['public.data'],
    webWildCards: ['.hyauth'],
  );

  @override
  Future<EncryptedBackupFileSelection?> pickBackup() async {
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [_typeGroup],
        confirmButtonText: 'Chọn backup',
      );
      if (file == null) return null;
      final length = await file.length();
      if (length <= 0 || length > EncryptedBackupFileCodec.maximumFileBytes) {
        throw const BackupFileIoException(
          'File backup rỗng hoặc vượt giới hạn 8 MiB.',
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > EncryptedBackupFileCodec.maximumFileBytes) {
        throw const BackupFileIoException('Không thể đọc file backup đã chọn.');
      }
      return EncryptedBackupFileSelection(bytes: bytes, displayName: file.name);
    } on BackupFileIoException {
      rethrow;
    } catch (_) {
      throw const BackupFileIoException(
        'Không thể mở file backup bằng system file picker.',
      );
    }
  }

  @override
  Future<BackupFileSaveResult> saveBackup({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > EncryptedBackupFileCodec.maximumFileBytes) {
      throw const BackupFileIoException(
        'Dữ liệu backup rỗng hoặc vượt giới hạn 8 MiB.',
      );
    }
    try {
      final file = file_selector.XFile.fromData(
        bytes,
        mimeType: 'application/octet-stream',
        name: suggestedName,
      );
      if (kIsWeb) {
        await file.saveTo(suggestedName);
        return BackupFileSaveResult.saved;
      }
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [file],
            fileNameOverrides: [suggestedName],
            subject: 'Backup Hyper Authenticator mã hóa',
            sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
          ),
        );
        return switch (result.status) {
          ShareResultStatus.success => BackupFileSaveResult.saved,
          ShareResultStatus.dismissed => BackupFileSaveResult.cancelled,
          ShareResultStatus.unavailable => throw const BackupFileIoException(
            'System share sheet không khả dụng trên thiết bị này.',
          ),
        };
      }
      if (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows) {
        final location = await file_selector.getSaveLocation(
          acceptedTypeGroups: const [_typeGroup],
          suggestedName: suggestedName,
          confirmButtonText: 'Lưu backup',
        );
        if (location == null) return BackupFileSaveResult.cancelled;
        await file.saveTo(location.path);
        return BackupFileSaveResult.saved;
      }
      throw const BackupFileIoException(
        'Platform hiện tại chưa hỗ trợ lưu backup file.',
      );
    } on BackupFileIoException {
      rethrow;
    } catch (_) {
      throw const BackupFileIoException(
        'Không thể lưu file backup bằng system file/share sheet.',
      );
    }
  }
}
