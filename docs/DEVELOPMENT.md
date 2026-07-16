# Hướng dẫn phát triển

## Điều kiện cần

- Flutter stable và Dart SDK tương thích `pubspec.yaml`.
- Git.
- Platform toolchain cho target được chọn.
- Supabase project không phải production cho luồng đăng nhập hiện tại.
- CocoaPods cho tích hợp plugin iOS và macOS hiện tại.

Kiểm tra máy:

    flutter doctor -v
    flutter --version
    dart --version
    scripts/agent/doctor.sh

## Thiết lập lần đầu

1. Tạo client configuration local:

       cp .env.example .env

2. Điền giá trị development an toàn:

       SUPABASE_URL=https://your-development-project.invalid
       SUPABASE_ANON_KEY=your-development-anon-key

3. Tải dependency:

       flutter pub get

4. Generate đăng ký Injectable sau khi dependency annotation thay đổi:

       dart run build_runner build --delete-conflicting-outputs

5. Chọn thiết bị và chạy:

       flutter devices
       flutter run

Không đặt service-role key, database password, SMTP credential, TOTP secret hoặc user token thật trong `.env`.

## Workflow hằng ngày

Trước khi sửa:

    git status --short --branch
    scripts/agent/context.sh
    scripts/agent/check.sh docs

Sau thay đổi chỉ có tài liệu:

    scripts/agent/check.sh docs

Sau thay đổi Dart:

    dart format lib test
    scripts/agent/check.sh quick

Sau thay đổi auth, storage, sync, routing, DI, plugin hoặc platform:

    scripts/agent/check.sh full

Đồng thời chạy build hoặc test platform bị ảnh hưởng và ghi kết quả.

## Cấu trúc repository

    lib/
      main.dart
      app.dart
      injection_container.dart
      core/
      features/
    assets/
    docs/
    scripts/agent/
    test/
    reset-password-web/
    android/
    ios/
    macos/
    web/
    windows/
    linux/

File được generate:

- `lib/injection_container.config.dart`

Không sửa generated output bằng tay. Hãy sửa annotation hoặc module rồi generate lại.

## Luồng thay đổi thường gặp

### Thêm hoặc sửa field tài khoản

Cập nhật:

1. Constructor, equality, `toJson` và `fromJson` của `AuthenticatorAccount`.
2. Parameter của add/update use case.
3. Round trip trong local data source.
4. Sync serialization và remote migration.
5. UI import, edit, export và display.
6. Test format cũ và hiện tại.
7. `DATA_MODELS.md` và `SUPABASE_INTEGRATION.md`.

### Thêm route

Cập nhật `AppRoutes` và `AppRouter`, định nghĩa behavior public/protected, thêm redirect test và ghi route trong `SYSTEM_DESIGN.md`.

### Thay đổi dependency injection

1. Sửa annotation hoặc `RegisterModule`.
2. Generate lại Injectable output.
3. Xác minh lifecycle: factory, lazy singleton hoặc shared provider.
4. Thêm test khi instance identity ảnh hưởng behavior.

### Thay đổi sync

Bắt đầu từ `SECURITY.md` và `SUPABASE_INTEGRATION.md`. Định nghĩa idempotency, conflict behavior, deletion propagation, migration và rollback trước implementation.

## Mô hình cấu hình local

Ứng dụng hiện load `.env` ở runtime như Flutter asset. Điều này khiến file bắt buộc để tạo asset bundle và đưa client configuration vào built application.

Cách này chỉ chấp nhận được với public client configuration như anon key, không phải cơ chế phân phối secret. Chiến lược dài hạn vẫn là một quyết định kiến trúc mở.

## Lưu ý theo platform

### Android

- Application ID: `app.hyperz.authenticator`.
- Release signing hiện fallback sang debug signing nếu không có release key; không phân phối artifact đó.
- Xác minh INTERNET, camera, biometric, backup và secure-storage behavior trong merged release manifest.

### iOS

- Xác minh bundle ID và signing trong Xcode.
- Đã có usage description cho camera và Face ID.
- URL handling cho password recovery vẫn cần deep-link configuration canonical.

### macOS

- Xác minh sandbox entitlement cho network client, camera, keychain và local-auth.
- Không suy luận release readiness chỉ từ CocoaPods cài thành công.

### Web và desktop

- Xác minh mọi plugin trên target.
- Xóa hoặc conditionally isolate import `dart:io` không được Web hỗ trợ.
- Ghi browser storage và threat model trước khi khẳng định Web support an toàn.

## Trang web khôi phục mật khẩu

Trang tĩnh này tách biệt Flutter Web app.

Chỉ chạy sau khi triển khai cơ chế inject public client configuration an toàn. Build argument của Compose hiện không được Dockerfile sử dụng.

Không bake server secret vào `script.js` hoặc Nginx image.

## Debug mà không làm lộ credential

- Redact giá trị sau `secret=` trong URI `otpauth`.
- Chỉ log account ID khi cần; ưu tiên fingerprint ngắn, một chiều để correlation.
- Không log email theo mặc định.
- Không in auth response, session, encryption key, salt hoặc full exception chứa request data.
- Dùng account tổng hợp và domain `.invalid`.

## Dọn và generate lại

Chỉ dùng clean khi chẩn đoán vấn đề generated file hoặc build cache:

    flutter clean
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs

Clean không thay thế việc hiểu nguyên nhân build failure. Phải bảo toàn thay đổi platform không liên quan trong working tree bẩn.
