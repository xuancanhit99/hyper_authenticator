import 'package:hyper_authenticator/core/error/failures.dart';

/// Ngữ cảnh thao tác dùng để chuyển [Failure] nội bộ thành copy an toàn cho UI.
///
/// Không đưa [Failure.message] từ server, storage hoặc exception ra màn hình.
/// Chỉ validation do ứng dụng kiểm soát mới được giữ nguyên để người dùng biết
/// chính xác trường dữ liệu cần sửa.
enum UserFailureContext {
  authCheck,
  signIn,
  signUp,
  recoverPassword,
  updatePassword,
  signOut,
  loadAccounts,
  addAccount,
  importAccounts,
  updateAccount,
  deleteAccount,
  sync,
}

String userFacingFailureMessage(
  Failure failure, {
  required UserFailureContext context,
}) {
  if (failure is ValidationFailure) return failure.message;
  if (failure is AccountNotFoundFailure) {
    return 'Không tìm thấy mã xác thực này trên thiết bị.';
  }

  return switch (context) {
    UserFailureContext.authCheck =>
      'Không thể kiểm tra phiên đăng nhập. Hãy thử lại sau.',
    UserFailureContext.signIn =>
      'Không thể đăng nhập. Kiểm tra email, mật khẩu và kết nối rồi thử lại.',
    UserFailureContext.signUp =>
      'Không thể tạo tài khoản. Email có thể đã được sử dụng hoặc hệ thống đang bận.',
    UserFailureContext.recoverPassword =>
      'Không thể gửi liên kết đặt lại mật khẩu lúc này. Hãy thử lại sau.',
    UserFailureContext.updatePassword =>
      'Không thể cập nhật mật khẩu. Hãy yêu cầu liên kết mới rồi thử lại.',
    UserFailureContext.signOut =>
      'Không thể đăng xuất lúc này. Hãy thử lại sau.',
    UserFailureContext.loadAccounts =>
      'Không thể đọc các mã đã lưu trên thiết bị.',
    UserFailureContext.addAccount => 'Không thể lưu mã xác thực trên thiết bị.',
    UserFailureContext.importAccounts =>
      'Không thể nhập các mã đã chọn. Dữ liệu hiện có vẫn được giữ nguyên.',
    UserFailureContext.updateAccount =>
      'Không thể lưu thay đổi. Mã hiện tại vẫn được giữ nguyên.',
    UserFailureContext.deleteAccount =>
      'Không thể xóa mã xác thực. Hãy thử lại.',
    UserFailureContext.sync =>
      'Không thể đồng bộ lúc này. Các mã trên thiết bị vẫn an toàn.',
  };
}
