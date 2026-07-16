# Trạng thái dự án

Được xác minh ngày 17 tháng 7 năm 2026 trên repository local có base HEAD là `6bf2598`. Working tree khi đó đã có thay đổi không liên quan ở iOS, macOS và `pubspec.lock`; các thay đổi đó không được đánh giá trong tài liệu này.

## Tổng quan

Hyper Authenticator là ứng dụng Flutter ở chất lượng alpha. Trải nghiệm TOTP local đã được triển khai phần lớn. Authentication và sync Supabase thủ công cũng đã có, nhưng các khoảng trống về bảo mật, mất dữ liệu, kiểm thử và cấu hình release khiến ứng dụng chưa thể dùng production với authenticator secret thật.

## Toolchain đã xác minh

- Flutter 3.44.6 stable.
- Dart 3.12.2.
- Constraint trong `pubspec`: Dart 3.7.2 hoặc tương thích.
- Dependency resolution trong `pubspec.lock`: Dart từ 3.10.0-0 trở lên.
- Phiên bản ứng dụng: 1.0.0+9.
- iOS và macOS đã được Flutter 3.44 migrate sang Swift Package Manager, đồng thời giữ CocoaPods làm fallback cho plugin chưa hỗ trợ SwiftPM.

## Ma trận tính năng

| Tính năng | Trạng thái | Ghi chú |
|---|---|---|
| Đăng nhập email/mật khẩu Supabase | Đã triển khai | Router bắt buộc, dù tài liệu cũ từng mô tả là tùy chọn |
| Đăng ký | Đã triển khai | Tên được lưu trong Supabase user metadata |
| Email khôi phục mật khẩu | Một phần | Mobile deep link và cấu hình web phụ trợ chưa hoàn thiện |
| Lưu TOTP local | Đã triển khai | FlutterSecureStorage với index key và JSON cho từng tài khoản |
| Tạo mã TOTP | Đã triển khai, còn lỗi | Domain nhận algorithm, digits, period; lưu tài khoản mới có thể làm mất giá trị không mặc định |
| Nhập QR bằng camera | Đã triển khai | Chỉ hỗ trợ `otpauth` TOTP |
| Nhập QR từ thư viện | Đã triển khai | Dùng MobileScanner phân tích ảnh |
| Nhập thủ công | Đã triển khai | Mặc định SHA1, 6 digits, 30 giây |
| Tìm kiếm, copy, sửa, xóa, xuất QR | Đã triển khai | UI chỉ có tiếng Anh |
| Khóa bằng credential thiết bị | Đã triển khai, còn thiếu | Dùng sinh trắc học hoặc credential của OS, không phải PIN riêng của app |
| Chọn theme | Đã triển khai | SharedPreferences |
| Gộp cloud | Đã triển khai, có nguy cơ mất dữ liệu | Gộp kiểu chỉ thêm rồi upload snapshot mang tính phá hủy |
| Ghi đè cloud | Đã triển khai, có nguy cơ mất dữ liệu | Xóa toàn bộ rồi chèn toàn bộ |
| E2EE phía client | Dự kiến | Luồng sync hiện tại không encrypt/decrypt |
| Automated test | Chưa triển khai | Chỉ có Flutter template test đã comment toàn bộ |
| CI | Chưa triển khai | Không có pipeline được track |
| Supabase schema tái lập được | Chưa triển khai | Không có migration hoặc generated schema contract |
| Cấu hình release production | Chưa sẵn sàng | Signing, permission, entitlement, privacy và xác minh platform còn thiếu |

## Release blocker

### Bảo mật và bảo vệ dữ liệu

1. `secretKey` TOTP được serialize và upload lên Supabase mà không mã hóa phía client.
2. URI `otpauth` đầy đủ, gồm secret, có thể bị ghi vào debug output khi quét QR.
3. Không thể xác minh RLS đã deploy vì repository không track migration hoặc policy.
4. Trạng thái lỗi local authentication chưa được router xem là explicit deny.
5. Privacy policy và data flow production phải luôn đồng bộ.

### Toàn vẹn dữ liệu

1. Cloud upload xóa mọi row remote trước khi chèn snapshot thay thế. Thao tác không atomic.
2. Merge chỉ dùng issuer và `accountName` viết thường làm key. Không cập nhật conflict hoặc biểu diễn deletion.
3. Lỗi merge một phần được log nhưng luồng vẫn có thể tiếp tục upload.
4. Lưu tài khoản local mới tạo lại entity mà không giữ algorithm, digits và period, nên âm thầm về default.
5. Countdown của danh sách tài khoản bị hard-code chu kỳ hiển thị 30 giây.
6. Logout gọi `deleteAll` trên namespace secure storage dùng chung và xóa tài khoản authenticator local mà không có cảnh báo riêng.
7. `SyncBloc` resolve một factory `AccountsBloc` khác instance UI đang hiển thị, khiến state UI có thể cũ.

### Sản phẩm và vận hành

1. Cấu hình Supabase và đăng nhập là bắt buộc khi khởi động; chưa có chế độ offline-only.
2. Deep link khôi phục mật khẩu chưa hoàn thiện.
3. `reset-password-web` truyền Docker build argument không được dùng, trong khi `script.js` để trống cấu hình Supabase.
4. Networking bản release Android và sandbox entitlement macOS cần được xác minh và sửa.
5. Tên sản phẩm chưa nhất quán giữa Hyper Authenticator, HyperZ và metadata template.
6. Không có file license rõ ràng được track.

## Quality baseline

Kết quả trước lần viết lại tài liệu:

    dart analyze --format=machine

Kết quả: 0 error, 29 warning, 72 info diagnostic.

    dart format --output=none --set-exit-if-changed lib test tool

Kết quả: phát hiện formatting drift trong 7 file Dart có sẵn.

    flutter test

Kết quả: checkout không có `.env` sẽ thất bại ở bước tạo asset bundle. Khi dùng `.env` placeholder local, test vẫn thất bại vì `test/widget_test.dart` không định nghĩa `main`.

Test inventory:

- `test/widget_test.dart` đã bị comment toàn bộ.
- Không có thư mục `integration_test`.
- Native test target iOS và macOS chỉ là template, không có product test.
- Không có CI workflow được track.

## Vị trí bằng chứng

- Bootstrap và Supabase bắt buộc: `lib/main.dart`.
- Auth redirect bắt buộc và local lock: `lib/core/router/app_router.dart`.
- Persistence tài khoản local: `lib/features/authenticator/data/datasources/authenticator_local_data_source.dart`.
- Tạo TOTP: `lib/features/authenticator/domain/usecases/generate_totp_code.dart`.
- Upload cloud snapshot: `lib/features/sync/data/datasources/supabase_sync_remote_data_source_impl.dart`.
- Hành vi merge: `lib/features/authenticator/presentation/bloc/accounts_bloc.dart`.
- Xóa storage khi logout: `lib/features/auth/presentation/bloc/auth_bloc.dart`.
- Trang recovery: `reset-password-web`.

## Cập nhật tài liệu này

Chỉ đổi trạng thái sau khi code và kết quả xác minh khớp nhau. Ghi command hoặc test tạo ra baseline mới. Chuyển defect đã xử lý sang release note hoặc ADR thay vì giữ cảnh báo lỗi thời tại đây.
