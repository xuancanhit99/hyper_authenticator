# Hyper Authenticator

Hyper Authenticator là ứng dụng Flutter đa nền tảng để lưu tài khoản TOTP và tạo
mã dùng một lần theo RFC 6238. Local vault hoạt động offline không cần đăng nhập;
Supabase authentication chỉ phục vụ tính năng cloud tùy chọn. Ứng dụng có app lock,
nhập/xuất QR và giao diện sáng/tối.

> Trạng thái dự án: **alpha**. Android, macOS và Web đã build thành công trên baseline hiện tại; iOS, Windows và Linux có runner cùng CI build nhưng vẫn cần xác minh trên thiết bị/hệ điều hành tương ứng. Cloud sync chưa có mã hóa đầu cuối (E2EE), vì vậy chưa nên dùng với secret production. Xem [Trạng thái dự án](docs/PROJECT_STATUS.md).

## Chức năng

- Dùng TOTP local không cần tài khoản hoặc network.
- Đăng ký, đăng nhập và khôi phục mật khẩu Web qua Supabase Auth cho cloud feature.
- Thêm tài khoản bằng camera, ảnh QR hoặc nhập thủ công.
- Parse URI `otpauth://totp` và validate Base32, SHA1/SHA256/SHA512, 6–8 chữ số cùng chu kỳ tùy chỉnh.
- Lưu TOTP bằng FlutterSecureStorage; tìm kiếm, sửa, xóa, sao chép và xuất QR.
- Khóa ứng dụng bằng sinh trắc học hoặc credential của OS trên platform được hỗ trợ.
- Giao diện sáng, tối hoặc theo hệ thống.
- Cloud sync release đang khóa; E2EE snapshot/recovery-key primitive đang rollout.

## Kiến trúc

Code được tổ chức theo feature và ba lớp chính:

    UI pages
      -> BLoCs
        -> use cases và repository contracts
          -> FlutterSecureStorage / SharedPreferences / Supabase

Tài liệu nên đọc trước:

- [Bản đồ tài liệu](docs/README.md)
- [Thiết kế hệ thống](docs/SYSTEM_DESIGN.md)
- [Trạng thái đã xác minh](docs/PROJECT_STATUS.md)
- [Mô hình bảo mật](docs/SECURITY.md)
- [Hợp đồng dành cho AI Agent](AGENTS.md)

## Thiết lập local

Yêu cầu Flutter stable tương thích `pubspec.yaml` và toolchain của platform đích.

    cp .env.example .env
    flutter pub get
    dart run build_runner build
    flutter run --dart-define-from-file=.env

`.env` chứa public client configuration:

    SUPABASE_URL=https://your-project.supabase.co
    SUPABASE_PUBLISHABLE_KEY=your-publishable-key
    PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/

File này bị Git bỏ qua và **không** được đóng gói như Flutter asset. Không đặt service-role key, database password hoặc secret phía server vào đây. Có thể chạy analyze, test và build không cấu hình Supabase; ứng dụng cần các define hợp lệ khi khởi động.

Quality gate:

    scripts/agent/doctor.sh
    scripts/agent/check.sh quick
    scripts/agent/check.sh full

Build theo host hoặc target:

    scripts/agent/build.sh host
    scripts/agent/build.sh android
    scripts/agent/build.sh web

Xem [Hướng dẫn phát triển](docs/DEVELOPMENT.md) và [Chiến lược kiểm thử](docs/TESTING_STRATEGY.md).

## Hỗ trợ nền tảng

| Platform | Build hiện tại | Giới hạn chức năng đáng chú ý |
|---|---|---|
| Android | Đã xác minh debug | Camera QR và device authentication |
| iOS | Runner + CI | Cần simulator/runtime hoặc thiết bị để xác minh local |
| macOS | Đã xác minh debug | Camera QR và device authentication |
| Web | Đã xác minh release | Không có device authentication; secure storage có threat model khác mobile |
| Windows | Runner + CI | Nhập TOTP thủ công; không có camera QR trong plugin hiện tại |
| Linux | Runner + CI | Nhập TOTP thủ công; không có camera QR hoặc device authentication |

`scripts/agent/build.sh` tự từ chối target không thể build trên host hiện tại.

## Lưu ý bảo mật

Plaintext compatibility sync luôn bị khóa trong release. E2EE primitives và schema
additive đã có nhưng onboarding/recovery-key UI cùng remote rollout chưa hoàn tất,
vì vậy cloud sync chưa phải encrypted backup production. Đọc
[Mô hình bảo mật](docs/SECURITY.md) trước khi dùng dữ liệu nhạy cảm.

## Đóng góp và giấy phép

Đọc [Hướng dẫn đóng góp](CONTRIBUTING.md). Source do dự án sở hữu được phát hành
theo [Apache License 2.0](LICENSE); logo, font, trademark và asset bên thứ ba vẫn
cần tuân theo quyền/license riêng của chúng.
