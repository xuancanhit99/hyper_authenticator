/// Phân biệt system UI do ứng dụng chủ động mở với việc người dùng rời app.
///
/// Privacy Shield vẫn che nội dung trong cả hai trường hợp. Guard chỉ ngăn
/// app-lock phá hủy route đang chờ kết quả từ document picker/share sheet.
abstract final class SystemUiInteractionGuard {
  static int _activeOperations = 0;

  static bool get isActive => _activeOperations > 0;

  static Future<T> run<T>(Future<T> Function() operation) async {
    _activeOperations++;
    try {
      return await operation();
    } finally {
      _activeOperations--;
    }
  }
}
