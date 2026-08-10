/// Metadata hiển thị trong UI.
///
/// [test/core/config/app_metadata_test.dart] khóa hai giá trị này với version
/// canonical trong pubspec để release không thể âm thầm hiển thị version cũ.
abstract final class AppMetadata {
  static const versionName = '1.1.2';
  static const buildNumber = '16';
  static const versionLabel = 'Phiên bản $versionName ($buildNumber)';
}
