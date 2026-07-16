# Hyper Authenticator

Hyper Authenticator là ứng dụng Flutter dùng để lưu tài khoản TOTP và tạo mã dùng một lần theo RFC 6238. Repository cũng bao gồm xác thực và đồng bộ cloud qua Supabase, khóa ứng dụng bằng thông tin xác thực của thiết bị, nhập/xuất QR và một trang web nhỏ phục vụ khôi phục mật khẩu.

> Trạng thái dự án: alpha. Luồng authenticator cục bộ đã được triển khai, nhưng đồng bộ cloud chưa có mã hóa đầu cuối (E2EE) và repository chưa sẵn sàng cho production. Hãy đọc [Trạng thái dự án](docs/PROJECT_STATUS.md) trước khi dùng secret 2FA thật.

## Chức năng đã triển khai

- Đăng ký và đăng nhập bằng email/mật khẩu qua Supabase.
- Thêm tài khoản TOTP bằng camera quét QR, ảnh trong thư viện hoặc nhập thủ công.
- Tạo mã TOTP SHA1, SHA256 hoặc SHA512 với số chữ số và chu kỳ tùy chỉnh.
- Tìm kiếm, sửa, xóa, sao chép và xuất tài khoản thành QR `otpauth`.
- Lưu bản ghi tài khoản qua FlutterSecureStorage.
- Tùy chọn khóa bằng sinh trắc học hoặc thông tin xác thực của thiết bị.
- Giao diện sáng, tối hoặc theo hệ thống.
- Gộp dữ liệu hoặc ghi đè cloud thủ công qua Supabase.

Một số luồng đã triển khai vẫn còn lỗi về tính đúng đắn hoặc bảo mật. Danh sách có thẩm quyền nằm trong [Trạng thái dự án](docs/PROJECT_STATUS.md).

## Kiến trúc

Mã Flutter được tổ chức theo feature và nhìn chung tuân theo ba lớp Presentation, Domain và Data:

    UI pages
      -> BLoCs
        -> use cases và repository contracts
          -> FlutterSecureStorage / SharedPreferences / Supabase

Nên bắt đầu từ:

- [Bản đồ tài liệu](docs/README.md)
- [Thiết kế hệ thống](docs/SYSTEM_DESIGN.md)
- [Trạng thái dự án đã xác minh](docs/PROJECT_STATUS.md)
- [Mô hình bảo mật](docs/SECURITY.md)
- [Hợp đồng dành cho AI Agent](AGENTS.md)

## Thiết lập local

Điều kiện cần:

- Flutter stable với Dart SDK tương thích `pubspec.yaml`.
- Platform tooling cho thiết bị đích.
- Một Supabase project cho luồng đăng nhập hiện đang bắt buộc.

Thiết lập:

    cp .env.example .env
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

File môi trường phải có `SUPABASE_URL` và `SUPABASE_ANON_KEY`. File này bị Git bỏ qua nhưng hiện được đóng gói như một Flutter asset. Không đặt Supabase service-role key hoặc bất kỳ server secret nào trong file này.

Chạy repository harness trước và sau mỗi thay đổi:

    scripts/agent/doctor.sh
    scripts/agent/check.sh quick

Dùng full gate khi test baseline đã sẵn sàng:

    scripts/agent/check.sh full

Xem [Hướng dẫn phát triển](docs/DEVELOPMENT.md) và [Chiến lược kiểm thử](docs/TESTING_STRATEGY.md) để biết chi tiết.

## Nền tảng

Flutter runner hiện có cho Android, iOS, Web, Windows, macOS và Linux. Có runner không đồng nghĩa nền tảng đã sẵn sàng phát hành. Android và iOS là hai mục tiêu mobile chính; mọi mục tiêu khác cần được xác minh rõ ràng về tính tương thích và bảo mật.

## Lưu ý bảo mật

Luồng sync hiện tại serialize TOTP secret trực tiếp vào row Supabase mà không có mã hóa phía client. Upload được thực hiện bằng cách xóa toàn bộ rồi chèn lại toàn bộ. Không quảng bá chức năng hiện tại là encrypted backup và không dùng với tài khoản production nhạy cảm cho đến khi xử lý xong các blocker trong [Mô hình bảo mật](docs/SECURITY.md).

## Đóng góp

Đọc [Hướng dẫn đóng góp](CONTRIBUTING.md). Mọi thay đổi lớn về kiến trúc hoặc bảo mật phải cập nhật tài liệu canonical tương ứng và thêm ADR nếu quyết định làm thay đổi một contract dài hạn.

## Giấy phép

Repository hiện chưa theo dõi file giấy phép. Không mặc định rằng mã nguồn có quyền được tái sử dụng cho đến khi chủ dự án bổ sung giấy phép rõ ràng.
