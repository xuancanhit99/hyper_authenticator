import 'windows_storage_migrator_stub.dart'
    if (dart.library.io) 'windows_storage_migrator_io.dart'
    as platform;

export 'windows_storage_migration_exception.dart';

Future<void> migrateWindowsStorageLayout() =>
    platform.migrateWindowsStorageLayout();
