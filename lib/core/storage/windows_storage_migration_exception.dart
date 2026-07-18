sealed class WindowsStorageMigrationException implements Exception {
  const WindowsStorageMigrationException();
}

final class WindowsStorageMigrationConflict
    extends WindowsStorageMigrationException {
  const WindowsStorageMigrationConflict();

  @override
  String toString() => 'WindowsStorageMigrationConflict';
}

final class WindowsStorageMigrationFailure
    extends WindowsStorageMigrationException {
  const WindowsStorageMigrationFailure();

  @override
  String toString() => 'WindowsStorageMigrationFailure';
}
