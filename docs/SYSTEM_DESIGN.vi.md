# Thiết kế hệ thống — Bản tiếng Việt

Tài liệu canonical là SYSTEM_DESIGN.md. Bản này tóm tắt kiến trúc hiện tại để onboarding bằng tiếng Việt và phải được cập nhật khi luồng chính thay đổi.

## Tổng quan

Hyper Authenticator là ứng dụng Flutter có hai biên lưu trữ:

- FlutterSecureStorage và SharedPreferences trên thiết bị;
- Supabase Auth và bảng synced_accounts cho đăng nhập và đồng bộ thủ công.

Ở implementation hiện tại, người dùng phải đăng nhập Supabase trước khi vào màn hình authenticator.

    Người dùng
      -> Flutter UI
        -> BLoC
          -> Use case / Repository
            -> Secure Storage
            -> SharedPreferences
            -> Supabase

## Khởi động

1. Load .env.
2. Khởi tạo dependency injection.
3. Đọc SUPABASE_URL và SUPABASE_ANON_KEY.
4. Khởi tạo Supabase.
5. Tạo ThemeProvider và các BLoC chính.
6. Kiểm tra session Supabase.
7. Kiểm tra khóa thiết bị.
8. Router chọn Login, Lock Screen hoặc Main.

Thiếu .env hoặc cấu hình Supabase làm app không khởi động bình thường.

## Module chính

- auth: đăng ký, đăng nhập, quên/đổi mật khẩu, logout.
- authenticator: account TOTP, QR, secure storage, device lock.
- sync: tải xuống, merge và upload snapshot Supabase.
- settings: biometric, sync và logout.
- main_navigation: hai tab Accounts và Settings.

Mỗi feature phần lớn được chia Presentation, Domain và Data. GetIt/Injectable quản lý dependency; BLoC quản lý state; Provider quản lý theme.

## Luồng account TOTP

AddAccountPage nhận camera QR, ảnh QR hoặc nhập tay. QR parser đọc issuer, label, secret, algorithm, digits và period. AccountsBloc gọi use case, repository và local data source để lưu JSON theo UUID trong FlutterSecureStorage.

Known gaps:

- Khi sinh UUID mới, data source chưa copy algorithm, digits và period nên có thể rơi về SHA1/6/30.
- Countdown UI luôn dùng chu kỳ 30 giây.
- QR scan hiện có log toàn bộ URI, có thể lộ secret.

## Khóa ứng dụng

Cờ biometric_enabled được lưu trong SharedPreferences. Nếu bật và thiết bị hỗ trợ, router đưa người dùng tới lock screen. Plugin local_auth cho phép biometric hoặc credential của hệ điều hành; đây không phải PIN riêng của ứng dụng.

App reset trạng thái unlock khi pause/detach và kiểm tra lại khi resume. Luồng lỗi cần được đổi sang fail-closed trước production.

## Đồng bộ

Sync là thao tác thủ công.

Merge hiện tại:

1. Download toàn bộ cloud accounts.
2. So sánh theo issuer và accountName viết thường.
3. Chỉ thêm bản cloud chưa tồn tại local.
4. Bỏ qua conflict.
5. Upload lại toàn bộ snapshot.

Overwrite hiện tại:

1. Xóa toàn bộ rows cloud của user.
2. Insert snapshot local.

Các giới hạn quan trọng:

- secretKey chưa được mã hóa đầu cuối;
- delete và insert không atomic;
- không có tombstone, version hoặc conflict policy;
- RLS/schema chưa có migration trong repo;
- SyncBloc có thể thao tác một AccountsBloc khác instance UI.

## Logout và dữ liệu

Logout hiện gọi deleteAll trên FlutterSecureStorage. Vì account TOTP dùng cùng storage, thao tác này xóa toàn bộ account local mà dialog không cảnh báo cụ thể.

## Password recovery

App có route đổi mật khẩu nhưng deep link chưa hoàn chỉnh. Thư mục reset-password-web có UI và lời gọi Supabase, nhưng URL/key chưa được inject đúng qua Docker.

## Trạng thái nền tảng

Android và iOS là target chính. Web, Windows, macOS và Linux có runner nhưng chưa được coi là release-ready. Mỗi platform cần test plugin, permission, entitlement, signing và secure-storage behavior riêng.

Đọc thêm:

- PROJECT_STATUS.md
- SECURITY.md
- DATA_MODELS.md
- SUPABASE_INTEGRATION.md
- E2EE_DESIGN.md
