import 'dart:io';
import 'dart:typed_data';

import 'windows_storage_migration_exception.dart';

/// Nhập storage từ ProductName từng được dùng ở bản pre-release vào đường dẫn
/// canonical tương thích với bản 1.0.0+9. Nguồn luôn được giữ nguyên.
final class WindowsStorageLayoutMigrator {
  WindowsStorageLayoutMigrator({
    required this.sourceDirectory,
    required this.targetDirectory,
  });

  static const markerFileName = '.ha-storage-layout-v1-imported';
  static const _sharedPreferencesFileName = 'shared_preferences.json';
  static const _secureStorageFileName = 'flutter_secure_storage.dat';

  final Directory sourceDirectory;
  final Directory targetDirectory;

  Future<void> migrate() async {
    try {
      await _migrate();
    } on WindowsStorageMigrationException {
      rethrow;
    } on Object {
      throw const WindowsStorageMigrationFailure();
    }
  }

  Future<void> _migrate() async {
    final marker = File(_childPath(targetDirectory, markerFileName));
    final markerType = await FileSystemEntity.type(
      marker.path,
      followLinks: false,
    );
    if (markerType == FileSystemEntityType.file) {
      return;
    }
    if (markerType != FileSystemEntityType.notFound) {
      throw const WindowsStorageMigrationFailure();
    }

    final sourceType = await FileSystemEntity.type(
      sourceDirectory.path,
      followLinks: false,
    );
    if (sourceType == FileSystemEntityType.notFound) {
      return;
    }
    if (sourceType != FileSystemEntityType.directory) {
      throw const WindowsStorageMigrationFailure();
    }

    final sourceFiles = await _allowedRegularFiles(sourceDirectory);
    if (sourceFiles.isEmpty) {
      return;
    }

    final targetType = await FileSystemEntity.type(
      targetDirectory.path,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.notFound) {
      await targetDirectory.create(recursive: true);
    } else if (targetType != FileSystemEntityType.directory) {
      throw const WindowsStorageMigrationFailure();
    }

    final targetFiles = await _allowedRegularFiles(targetDirectory);
    final sourceVault = Map<String, File>.fromEntries(
      sourceFiles.entries.where((entry) => _isVaultFile(entry.key)),
    );
    final targetVault = Map<String, File>.fromEntries(
      targetFiles.entries.where((entry) => _isVaultFile(entry.key)),
    );

    if (sourceVault.isNotEmpty &&
        targetVault.isNotEmpty &&
        !await _sameFileSet(sourceVault, targetVault)) {
      throw const WindowsStorageMigrationConflict();
    }

    final filesToCopy = <MapEntry<String, File>>[];
    if (targetVault.isEmpty) {
      filesToCopy.addAll(sourceVault.entries);
    }
    if (sourceFiles.containsKey(_sharedPreferencesFileName) &&
        !targetFiles.containsKey(_sharedPreferencesFileName)) {
      filesToCopy.add(
        MapEntry(
          _sharedPreferencesFileName,
          sourceFiles[_sharedPreferencesFileName]!,
        ),
      );
    }

    final createdFiles = <File>[];
    try {
      for (final entry in filesToCopy) {
        final destination = File(_childPath(targetDirectory, entry.key));
        await _copyAtomically(entry.value, destination);
        createdFiles.add(destination);
      }
      await _writeMarkerAtomically(marker);
    } on Object {
      for (final file in createdFiles.reversed) {
        try {
          if (await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.file) {
            await file.delete();
          }
        } on Object {
          // Best-effort rollback; nguồn không bao giờ bị sửa hoặc xóa.
        }
      }
      rethrow;
    }
  }

  Future<Map<String, File>> _allowedRegularFiles(Directory directory) async {
    final files = <String, File>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final name = _baseName(entity.path);
      if (_isVaultFile(name) || name == _sharedPreferencesFileName) {
        files[name] = File(entity.path);
      }
    }
    return files;
  }

  bool _isVaultFile(String name) =>
      name == _secureStorageFileName || name.endsWith('.secure');

  Future<bool> _sameFileSet(
    Map<String, File> source,
    Map<String, File> target,
  ) async {
    if (source.length != target.length ||
        !source.keys.every(target.containsKey)) {
      return false;
    }
    for (final name in source.keys) {
      if (!await _sameBytes(source[name]!, target[name]!)) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _sameBytes(File first, File second) async {
    if (await first.length() != await second.length()) {
      return false;
    }
    final firstBytes = await first.readAsBytes();
    final secondBytes = await second.readAsBytes();
    return _bytesEqual(firstBytes, secondBytes);
  }

  bool _bytesEqual(Uint8List first, Uint8List second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _copyAtomically(File source, File destination) async {
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const WindowsStorageMigrationFailure();
    }
    final temporary = File(_temporaryPath(destination));
    try {
      await source.copy(temporary.path);
      if (!await _sameBytes(source, temporary)) {
        throw const WindowsStorageMigrationFailure();
      }
      await temporary.rename(destination.path);
    } finally {
      if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temporary.delete();
      }
    }
  }

  Future<void> _writeMarkerAtomically(File marker) async {
    final temporary = File(_temporaryPath(marker));
    try {
      await temporary.writeAsString('v1\n', flush: true);
      await temporary.rename(marker.path);
    } finally {
      if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await temporary.delete();
      }
    }
  }

  String _temporaryPath(File destination) =>
      '${destination.path}.ha-migrate-$pid-${DateTime.now().microsecondsSinceEpoch}.tmp';

  String _childPath(Directory directory, String name) =>
      '${directory.path}${Platform.pathSeparator}$name';

  String _baseName(String path) {
    final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
    return separatorIndex < 0 ? path : path.substring(separatorIndex + 1);
  }
}
