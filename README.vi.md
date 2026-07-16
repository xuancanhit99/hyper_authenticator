# Hyper Authenticator

Hyper Authenticator là ứng dụng Flutter dùng để lưu tài khoản 2FA và tạo mã TOTP theo RFC 6238. Repo còn có đăng nhập Supabase, đồng bộ cloud thủ công, khóa ứng dụng bằng thông tin xác thực của thiết bị, nhập/xuất QR và một trang web nhỏ cho luồng khôi phục mật khẩu.

> Trạng thái: alpha. Luồng authenticator cục bộ đã hoạt động, nhưng đồng bộ cloud chưa có mã hóa đầu cuối và project chưa sẵn sàng cho production. Hãy đọc [Project Status](docs/PROJECT_STATUS.md) trước khi dùng secret 2FA thật.

Tài liệu kỹ thuật canonical được viết bằng tiếng Anh để giảm trôi nội dung giữa nhiều bản dịch. Trang này là bản tổng quan tiếng Việt.

## Tính năng hiện có

- Đăng ký và đăng nhập email/password qua Supabase.
- Thêm tài khoản bằng camera QR, ảnh trong thư viện hoặc nhập thủ công.
- Tạo TOTP với SHA1, SHA256, SHA512; hỗ trợ digits và period tùy chỉnh ở domain model.
- Tìm kiếm, chỉnh sửa, xóa, copy mã và xuất lại QR otpauth.
- Lưu account trong FlutterSecureStorage.
- Khóa app tùy chọn bằng sinh trắc học hoặc PIN/passcode của hệ điều hành.
- Giao diện sáng, tối hoặc theo hệ thống.
- Đồng bộ thủ công theo kiểu merge hoặc ghi đè cloud.

Một số luồng đã có nhưng còn lỗi correctness/security. Danh sách chuẩn nằm trong docs/PROJECT_STATUS.md.

## Bắt đầu nhanh

    cp .env.example .env
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter run

File .env cần SUPABASE_URL và SUPABASE_ANON_KEY. Tuyệt đối không đặt service-role key hoặc secret phía server trong ứng dụng.

Kiểm tra môi trường và chất lượng:

    scripts/agent/doctor.sh
    scripts/agent/check.sh quick

## Nên đọc gì?

- [Mục lục tài liệu](docs/README.md)
- [Kiến trúc tiếng Việt](docs/SYSTEM_DESIGN.vi.md)
- [Baseline và known gaps](docs/PROJECT_STATUS.md)
- [Mô hình bảo mật](docs/SECURITY.md)
- [Roadmap ưu tiên](docs/ROADMAP.md)
- [Quy tắc dành cho AI Agent](AGENTS.md)

## Cảnh báo bảo mật

Sync hiện gửi secret TOTP lên Supabase dưới dạng dữ liệu có thể đọc được và upload theo cách xóa toàn bộ rồi insert lại. Chưa được gọi đây là backup mã hóa hoặc dùng với tài khoản production trước khi hoàn thành các blocker trong docs/SECURITY.md.

## License

Repo hiện chưa có file license. Không mặc định rằng mã nguồn được phép tái sử dụng cho đến khi chủ project bổ sung license rõ ràng.
