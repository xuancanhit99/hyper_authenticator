import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'windows_storage_layout_migrator.dart';

const _alternateProductName = 'Hyper Authenticator';

Future<void> migrateWindowsStorageLayout() async {
  if (!Platform.isWindows) {
    return;
  }

  final canonicalDirectory = await getApplicationSupportDirectory();
  final alternateDirectory = Directory(
    '${canonicalDirectory.parent.path}'
    '${Platform.pathSeparator}$_alternateProductName',
  );
  await WindowsStorageLayoutMigrator(
    sourceDirectory: alternateDirectory,
    targetDirectory: canonicalDirectory,
  ).migrate();
}
