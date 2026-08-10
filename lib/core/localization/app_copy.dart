/// Catalog tiếng Việt cho tên sản phẩm và thuật ngữ dùng lặp lại.
///
/// App hiện chỉ phát hành một locale. Chỉ đưa các thuật ngữ phải nhất quán giữa
/// native app và Chrome Extension vào đây; câu theo ngữ cảnh vẫn ở gần widget
/// để tránh biến catalog thành một danh sách khó bảo trì.
abstract final class AppCopy {
  static const appName = 'Hyper Authenticator';

  static const accounts = 'Tài khoản';
  static const settings = 'Cài đặt';
  static const about = 'Giới thiệu';

  static const service = 'Dịch vụ';
  static const serviceExample = 'Ví dụ: Google';
  static const account = 'Tài khoản';
  static const accountExample = 'Ví dụ: user@example.com';
  static const setupKey = 'Khóa thiết lập';

  static const cancel = 'Hủy';
  static const retry = 'Thử lại';
}
