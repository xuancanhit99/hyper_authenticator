# Hyper Authenticator

Hyper Authenticator là ứng dụng Flutter đa nền tảng để lưu tài khoản TOTP và tạo
mã dùng một lần theo RFC 6238. Local vault hoạt động offline không cần đăng nhập;
Supabase authentication chỉ phục vụ backup cloud mã hóa đầu cuối tùy chọn. Ứng
dụng có app lock, nhập QR và giao diện sáng/tối.

> Trạng thái dự án: **production baseline kỹ thuật; GitHub Releases là kênh phân
> phối binary ưu tiên trong giai đoạn hiện tại**. Web đang chạy production.
> Android có APK đã ký; Windows/Linux có package chưa ký. Các binary chỉ được phát
> hành dưới dạng pre-release với checksum và cảnh báo rõ ràng. App store, signing
> cho stable,
> device test, SMTP mailbox và public legal/support metadata được hoãn sang giai
> đoạn sau. Xem [Trạng thái dự án](docs/PROJECT_STATUS.md).

## Tải ứng dụng

- Web: [authenticator.hyperz.xyz](https://authenticator.hyperz.xyz/).
- GitHub Preview hiện tại: [v1.1.0-preview.4](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.0-preview.4).

GitHub Preview có Android APK signed, Windows x64 installer và Linux amd64 Debian
package. Luôn kiểm tra `SHA256SUMS.txt`; Android có thể yêu cầu cho phép cài từ
browser/GitHub, còn Windows SmartScreen có thể cảnh báo vì installer chưa code-sign.
iOS và macOS chưa được phân phối binary ở giai đoạn này. Android signed APK đã
pass tag CI, public-download/signature gate và emulator clean-install/
vault-retaining upgrade; camera/biometric trên thiết bị thật vẫn là gate sau.

## Chức năng

- Dùng TOTP local không cần tài khoản hoặc network.
- Đăng ký, đăng nhập và khôi phục mật khẩu Web qua Supabase Auth cho backup cloud.
- Thêm tài khoản bằng camera, ảnh QR hoặc nhập thủ công.
- Parse URI `otpauth://totp` và validate Base32, SHA1/SHA256/SHA512, 6–8 chữ số cùng chu kỳ tùy chỉnh.
- Lưu TOTP bằng FlutterSecureStorage; tìm kiếm, sửa, xóa và sao chép.
- Khóa ứng dụng bằng sinh trắc học hoặc credential của OS trên platform được hỗ trợ.
- Giao diện sáng, tối hoặc theo hệ thống.
- Backup cloud mã hóa đầu cuối do người dùng kích hoạt trên native platform, có
  recovery key và conflict resolution.

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

    flutter pub get
    dart run build_runner build
    flutter run

Lệnh trên khởi động chế độ local-only. Chỉ tạo file `.env` khi cần đăng nhập và
backup cloud:

    cp .env.example .env
    flutter run --dart-define-from-file=.env

`.env` chứa public client configuration:

    SUPABASE_URL=https://your-project.supabase.co
    SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
    PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/

File này bị Git bỏ qua và **không** được đóng gói như Flutter asset. Không đặt
service-role key, database password hoặc secret phía server vào đây. Thiếu toàn
bộ cấu hình cloud là trạng thái local-only hợp lệ; cấu hình dở dang bị từ chối.

Kiểm tra public config mà không in giá trị:

    dart run tool/agent/check_release_config.dart .env

Quality gate:

    scripts/agent/doctor.sh
    scripts/agent/check.sh quick
    scripts/agent/check.sh app
    scripts/agent/check.sh backend
    scripts/agent/check.sh release
    scripts/agent/check.sh infra
    scripts/agent/check.sh full

Build theo host hoặc target:

    scripts/agent/build.sh host
    scripts/agent/build.sh host .env
    scripts/agent/build.sh android
    scripts/agent/build.sh web

Web production image và Linux compile cô lập:

    web-deployment/test.sh
    web-deployment/build-image.sh hyper-authenticator-web:1.1.0
    scripts/agent/build_linux_container.sh

Sau khi tạo `build/web` bằng public release config hợp lệ, chạy thêm browser
artifact smoke để xác minh Flutter engine mount, semantics và local-vault shell:

    scripts/agent/web_runtime_smoke.sh

Command có đối số `.env` validate public release contract trước khi build; không
có đối số chỉ là compile smoke. Xem [Hướng dẫn phát triển](docs/DEVELOPMENT.md)
và [Chiến lược kiểm thử](docs/TESTING_STRATEGY.md).

## Hỗ trợ nền tảng

| Platform | Build hiện tại | Giới hạn chức năng đáng chú ý |
|---|---|---|
| Android | Signed APK pre-release | Camera QR và device authentication; còn gate thiết bị thật |
| iOS | Đã xác minh simulator | Cần device và signing để release |
| macOS | Đã xác minh compile unsigned | Cần signing để test Keychain/runtime và release |
| Web | Production HTTPS | Không có device authentication hoặc backup cloud E2EE |
| Windows | Hosted runtime + unsigned NSIS Preview | Nhập thủ công + E2EE; không có camera QR |
| Linux | Hosted runtime + unsigned `.deb` Preview | Nhập thủ công + E2EE; chưa KDE/physical desktop |

`scripts/agent/build.sh` tự từ chối target không thể build trên host hiện tại.

## Lưu ý bảo mật

Client không còn source/runtime path để backup TOTP secret ở dạng plaintext.
Migration retirement chỉ drop legacy table khi xác minh bảng rỗng và fail closed
nếu còn row; trạng thái deploy production được ghi riêng trong
[Trạng thái dự án](docs/PROJECT_STATUS.md). E2EE vẫn không thay thế việc người dùng
giữ recovery key; mất mọi thiết bị cùng recovery key có thể làm mất khả năng khôi
phục. Revoke Supabase session không phải remote wipe hoặc cryptographic device
exclusion; generic vault-key rotation vẫn cấp wrap mới cho mọi active device có
membership proof hợp lệ. Đọc
[Mô hình bảo mật](docs/SECURITY.md) trước khi dùng dữ liệu nhạy cảm.

## Đóng góp và giấy phép

Đọc [Hướng dẫn đóng góp](CONTRIBUTING.md). Source do dự án sở hữu được phát hành
theo [Apache License 2.0](LICENSE). Release chỉ bundle branding do owner kiểm soát;
asset bên thứ ba mới phải có provenance/license/NOTICE theo
[ADR-0007](docs/adr/0007-require-provenance-for-distributed-assets.md).
