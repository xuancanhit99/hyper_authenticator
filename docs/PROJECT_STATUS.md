# Trạng thái dự án

Baseline được xác minh ngày **17 tháng 7 năm 2026** trên macOS 26.5.1.

## Tổng quan

Hyper Authenticator là ứng dụng Flutter alpha hướng tới Android, iOS, macOS, Windows, Linux và Web. Luồng TOTP local, authentication, app lock và sync thủ công đã có. Đợt hiện đại hóa hiện tại đã nâng toolchain/dependency, sửa các lỗi đúng đắn quan trọng, bổ sung test/CI và đưa ba target có thể chạy trên host hiện tại về trạng thái build được.

Ứng dụng **chưa sẵn sàng production** với secret thật vì cloud sync vẫn plaintext, upload không atomic và repository chưa có Supabase schema/RLS migration có thể tái lập.

## Baseline toolchain và dependency

- Flutter 3.44.6 stable, Dart 3.12.2.
- Dart constraint: `^3.12.0`.
- Phiên bản ứng dụng: `1.0.0+9`.
- Mọi direct dependency ở phiên bản mới nhất mà dependency solver của baseline này chấp nhận.
- `build_runner` giữ ở 2.15.1 vì 2.15.2 xung đột với version `meta` được Flutter test SDK pin.
- Apple runner dùng Swift Package Manager; CocoaPods integration và lockfile cũ đã được loại bỏ.

## Kết quả xác minh

| Kiểm tra | Kết quả |
|---|---|
| `flutter doctor -v` | Không có lỗi toolchain |
| `dart format --output=none --set-exit-if-changed lib test tool` | Pass |
| `flutter analyze` | Pass, không có diagnostic |
| `flutter test` | 10 test pass |
| Android `flutter build apk --debug` | Pass |
| Web `flutter build web --release` | Pass |
| macOS `flutter build macos --debug` | Pass |
| iOS simulator build | Chưa chạy được local vì thiếu iOS 26.5 Simulator Runtime |
| Windows/Linux build | Không thể build native trên macOS; CI đã có job tương ứng |

Test hiện có bao phủ JSON round-trip, compatibility với record cũ, parse URI `otpauth`, validation tham số TOTP, RFC 6238 SHA1 known-answer vector và auth-state sau sign-in/sign-up. Chưa có widget/integration test đầy đủ.

## Ma trận platform

| Platform | Trạng thái | Ghi chú |
|---|---|---|
| Android | Đã build local | Camera QR, image import và device authentication được bật |
| iOS | Đã cấu hình | SwiftPM, entitlement và usage description đã cập nhật; cần runtime/thiết bị để xác minh |
| macOS | Đã build local | Sandbox network/camera đã cấu hình; release signing/keychain cần xác minh |
| Web | Đã build local | Camera QR được hỗ trợ; không bật local authentication |
| Windows | CI build | Nhập thủ công hoạt động theo thiết kế; scanner bị ẩn vì plugin không hỗ trợ |
| Linux | CI build | Nhập thủ công hoạt động theo thiết kế; scanner và local authentication bị ẩn |

Có artifact build không đồng nghĩa platform đã đủ điều kiện phát hành; release signing, installer, permission và kiểm thử thiết bị vẫn theo [Deployment](DEPLOYMENT.md).

## Cải tiến đã áp dụng

- Cấu hình Supabase chuyển từ asset `.env` sang compile-time `dart-define`.
- Gỡ dependency không dùng; nâng toàn bộ direct dependency có thể nâng.
- Parse TOTP tập trung, validate Base32/algorithm/digits/period và không log QR secret.
- Giữ nguyên algorithm, digits và period khi tạo record có UUID.
- Logout không còn xóa toàn bộ TOTP local.
- Auth, account và sync dùng cùng shared BLoC instance.
- App lock fail closed khi authentication lỗi và relock khi app rời foreground.
- Ẩn scanner/local-auth trên platform plugin không hỗ trợ.
- Sửa truy vấn `hasRemoteData` dùng đúng `account_id`.
- Lỗi merge không còn bị nuốt rồi tiếp tục upload.
- Android nâng Gradle/AGP/Kotlin/JVM; Apple chuyển hoàn toàn sang SwiftPM.
- Thêm CI đa nền tảng, Dependabot và build harness cho AI Agent.

## Release blocker còn lại

### Bảo mật và dữ liệu

1. TOTP secret được upload lên Supabase ở dạng plaintext; chưa có E2EE.
2. Upload cloud xóa snapshot cũ rồi chèn snapshot mới, không atomic và không idempotent.
3. Merge dùng `issuer + accountName` làm identity, chưa có conflict protocol hoặc tombstone.
4. Không có migration/schema/RLS policy được version control và cross-user test.
5. Secure storage trên Web có threat model khác native và cần review riêng.

### Tính đúng đắn và sản phẩm

1. Countdown UI vẫn giả định chu kỳ 30 giây cho mọi account.
2. Local storage record/index là thao tác nhiều bước, chưa có recovery protocol.
3. Supabase authentication vẫn bắt buộc; chưa có offline-only mode.
4. Password recovery deep link và trang web recovery chưa được cấu hình hoàn chỉnh.
5. `reset-password-web` chưa có cơ chế inject public configuration có thể deploy.

### Phát hành

1. Chưa có license, release signing/notarization, installer và store metadata hoàn chỉnh.
2. iOS cần xác minh trên simulator/thiết bị; Windows và Linux cần xác minh ngoài CI.
3. Chưa có integration test cho storage, auth, lock, sync, recovery và RLS.
4. Một số plugin Android vẫn dùng Kotlin Gradle Plugin legacy và phát cảnh báo tương thích tương lai từ Flutter; build hiện tại vẫn pass.

## CI và automation

- `.github/workflows/ci.yml` pin Flutter 3.44.6 và build Android, iOS simulator, macOS, Web, Windows, Linux.
- Quality job chạy documentation gate, generated-code drift, format, analyze và test.
- `.github/dependabot.yml` kiểm tra dependency Pub và GitHub Actions hằng tuần.

## Cập nhật tài liệu này

Chỉ đổi trạng thái khi có command hoặc test làm bằng chứng. Nếu một platform chưa được chạy trên host/device tương ứng, ghi **chưa xác minh** thay vì suy luận từ việc runner tồn tại.
