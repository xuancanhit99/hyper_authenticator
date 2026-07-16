# Thiết kế hệ thống

Tài liệu này mô tả hệ thống đang tồn tại trong repository. Thiết kế encryption và hành vi tương lai được ghi riêng, không được xem là đã triển khai.

## Bối cảnh hệ thống

Hyper Authenticator là Flutter client có hai ranh giới persistence:

- storage trên thiết bị cho tài khoản authenticator và preference;
- Supabase Auth và PostgreSQL cho user session và sync thủ công tùy chọn.

Sản phẩm hiện bắt buộc xác thực Supabase trước khi dùng UI authenticator.

~~~mermaid
flowchart LR
    User["Người dùng"] --> App["Ứng dụng Flutter"]
    App --> DeviceAuth["Sinh trắc học / credential của OS"]
    App --> SecureStorage["FlutterSecureStorage"]
    App --> Preferences["SharedPreferences"]
    App --> SupabaseAuth["Supabase Auth"]
    App --> SupabaseDB["Supabase synced_accounts"]
    Recovery["Trang web recovery tĩnh"] --> SupabaseAuth
~~~

## Bootstrap

Thứ tự khởi động runtime:

1. Khởi tạo Flutter binding.
2. Load asset `.env` ở root.
3. Chạy đăng ký Injectable/GetIt và pre-resolution SharedPreferences.
4. `AppConfig` đọc `SUPABASE_URL` và `SUPABASE_ANON_KEY`.
5. Khởi tạo Supabase.
6. Cung cấp `ThemeProvider`, `AuthBloc`, `LocalAuthBloc`, `AccountsBloc` và `SettingsBloc`.
7. `AuthBloc` kiểm tra user Supabase hiện tại.
8. `LocalAuthBloc` kiểm tra có cần khóa thiết bị đã cấu hình hay không.
9. GoRouter chọn login, lock hoặc main navigation shell.

Thiếu hoặc để trống cấu hình Supabase sẽ dừng bootstrap bình thường và hiển thị màn hình lỗi khởi tạo.

## Điều hướng

| Route | Mục đích | Quyền truy cập |
|---|---|---|
| `/login` | Đăng nhập | Công khai |
| `/register` | Đăng ký | Công khai |
| `/forgot-password` | Yêu cầu email recovery | Công khai |
| `/update-password` | Đặt mật khẩu mới | Route đã có nhưng recovery/deep-link chưa hoàn thiện |
| `/` | Tab Accounts và Settings | Đã xác thực Supabase |
| `/add-account` | Thêm tài khoản TOTP | Đã xác thực Supabase |
| `/edit-account` | Sửa tài khoản truyền qua route state | Đã xác thực Supabase |
| `/lock-screen` | Challenge credential thiết bị | Đã xác thực và cần khóa |

Router refresh từ stream của `AuthBloc` và `LocalAuthBloc`. Tài liệu cũ mô tả xác thực Supabase là tùy chọn không còn đúng với router hiện tại.

## Kiến trúc Flutter

Code được tổ chức theo feature:

    lib/
      core/
      features/
        auth/
        authenticator/
        main_navigation/
        settings/
        sync/

Phần lớn feature có ba lớp:

- **Presentation:** page, widget, event, state và BLoC.
- **Domain:** entity, repository contract và use case.
- **Data:** implementation Supabase và local storage.

GetIt và Injectable khởi tạo dependency. Theme state dùng Provider. Kết quả thường dùng `Either` của fpdart để chuyển failure qua domain boundary mà không throw.

### Lưu ý về quyền sở hữu instance

`AccountsBloc` được đăng ký dạng factory. Provider cấp ứng dụng sở hữu một instance, trong khi `SyncBloc` tạo qua factory lại resolve một `AccountsBloc` khác. Cả hai truy cập được cùng storage repository nhưng không chia sẻ UI state. Phối hợp cross-feature phải dùng instance được chia sẻ rõ ràng hoặc mô hình orchestration ở tầng repository.

## Luồng tài khoản authenticator

### Nhập tài khoản

1. `AddAccountPage` nhận field thủ công, barcode từ camera hoặc ảnh.
2. QR phải dùng scheme `otpauth` và host `totp`.
3. Page parse issuer, label, secret, algorithm, digits và period.
4. `AccountsBloc` gọi `AddAccount`.
5. `AuthenticatorRepository` ghi qua `AuthenticatorLocalDataSource`.
6. Data source gán UUID và ghi JSON vào secure storage.
7. UUID tài khoản được thêm vào secure-storage index.

Khoảng trống đã biết: khi gán UUID, implementation hiện tại tạo lại entity mà không sao chép algorithm, digits và period. Input không mặc định có thể âm thầm thành SHA1, 6 digits và 30 giây.

### Đọc và tạo mã

1. `AccountsBloc` đọc account index rồi đọc từng record JSON.
2. `AccountsPage` gọi `GenerateTotpCode` cho mỗi tài khoản.
3. Package `otp` tính mã từ clock local và tham số đã lưu.
4. UI refresh mỗi giây và copy mã hiện tại khi người dùng chạm.

Khoảng trống đã biết: countdown hiển thị và trigger tạo mã mới dùng chu kỳ cố định 30 giây, kể cả khi account có period khác.

### Cập nhật và xóa

Update ghi đè record JSON có cùng ID. Delete xóa record rồi xóa ID khỏi index. Không có transactional boundary giữa thao tác record và index, vì vậy cần test recovery khi chỉ một phần thao tác thành công.

## Khóa thiết bị

Preference `biometric_enabled` được lưu trong SharedPreferences.

- Khi tắt hoặc thiết bị không hỗ trợ, `LocalAuthBloc` emit success và ứng dụng tiếp tục.
- Khi bật và được hỗ trợ, router chuyển tới lock screen.
- `local_auth.authenticate` chấp nhận sinh trắc học hoặc credential thiết bị do `biometricOnly` không được bật.
- Khi pause hoặc detach, lifecycle handler reset auth state.
- Khi resume, ứng dụng yêu cầu kiểm tra lại.

Đây là app gate, không phải cryptographic protection cho từng secure-storage record. Error state phải được route theo fail-closed trước production.

## Xác thực Supabase

`AuthRemoteDataSource` bọc các thao tác:

- `signInWithPassword`;
- `signUp` cùng name metadata tùy chọn;
- `resetPasswordForEmail`;
- `updateUser` để đổi mật khẩu;
- `signOut`;
- auth-state stream.

Remember Me chỉ lưu email và trạng thái checkbox trong SharedPreferences, không chủ ý persist mật khẩu.

Xử lý sign-out hiện tại còn xóa mọi entry FlutterSecureStorage. Vì tài khoản authenticator dùng cùng storage instance, sign-out sẽ xóa tài khoản local.

## Đồng bộ

Sync được kích hoạt thủ công. Bật sync chỉ lưu một flag SharedPreferences.

### Luồng merge

1. Download mọi tài khoản remote của user hiện tại.
2. Đọc tài khoản local.
3. Tạo identity key từ issuer và `accountName` viết thường.
4. Thêm account remote có key chưa tồn tại ở local.
5. Bỏ qua key đã có mà không so sánh field hoặc giải quyết conflict.
6. Đọc snapshot local sau khi merge.
7. Upload toàn bộ snapshot.

### Luồng overwrite

1. Lấy danh sách account hiện tại của UI.
2. Xóa mọi row remote của user.
3. Chèn snapshot được cung cấp.

### Thuộc tính hiện tại

- Secret được upload dưới dạng field JSON có thể đọc.
- Upload không atomic.
- Không có tombstone hoặc rule truyền deletion.
- Không có version vector, so sánh `updated_at` hoặc policy conflict đa thiết bị.
- Server schema và RLS không thể tái lập từ migration được track.
- Last sync time được suy ra từ `updated_at` mới nhất trên remote.

Xem [Bảo mật](SECURITY.md), [Tích hợp Supabase](SUPABASE_INTEGRATION.md) và [Thiết kế E2EE](E2EE_DESIGN.md).

## Trang web khôi phục mật khẩu

`reset-password-web` là trang HTML, CSS và JavaScript tĩnh:

1. nhận Supabase recovery session;
2. validate mật khẩu mới và xác nhận;
3. gọi `Supabase auth.updateUser`.

Cấu hình container hiện chưa hoàn thiện: Compose truyền build argument, Dockerfile không sử dụng, còn `script.js` có hằng cấu hình trống.

## Trạng thái platform

Flutter 3.44 đã migrate project Darwin sang `FlutterGeneratedPluginSwiftPackage`. Plugin có SwiftPM support được resolve qua `Package.resolved`; plugin chưa hỗ trợ vẫn được tích hợp bằng Podfile và Podfile.lock. Cả hai bộ lockfile là một phần của build contract.

| Platform | Runner | Trạng thái phát hành |
|---|---|---|
| Android | Có | Mục tiêu chính; permission và release signing cần hardening |
| iOS | Có | Mục tiêu chính; đã có mô tả camera/Face ID, deep link còn thiếu |
| macOS | Có | Cần xác minh network client, sandbox entitlement và plugin |
| Web | Có | Metadata còn dấu vết template; cần xác minh plugin và tương thích `dart:io` |
| Windows | Có | Chỉ có runner; cần xác minh đầy đủ tính năng |
| Linux | Có | Chỉ có runner; chưa phải mục tiêu được quảng bá hoặc xác minh |

Không platform nào được xem là supported cho đến khi vượt qua release gate được ghi cho platform đó.

## Xử lý lỗi

Repository thường chuyển storage, authentication và server exception thành `Failure`. BLoC ánh xạ failure thành state. Các vấn đề còn lại:

- catch quá rộng làm mất cấu trúc diagnostic;
- còn `print` và `debugPrint` trong production path;
- emit success sau lỗi sync một phần;
- routing khi local-auth error;
- chưa có telemetry policy hoặc redaction layer.

## Bản đồ tác động thay đổi

- Field persist mới: cập nhật entity JSON, local round-trip test, remote contract, migration plan và `DATA_MODELS.md`.
- Route hoặc auth rule mới: cập nhật router test và tài liệu này.
- Hành vi sync mới: cập nhật conflict semantic, `SECURITY.md`, `SUPABASE_INTEGRATION.md` và test thao tác phá hủy.
- Plugin hoặc platform mới: cập nhật entitlement/permission, dependency policy và `DEPLOYMENT.md`.
- Hành vi encryption mới: thêm ADR, format version, migration, recovery path và E2EE test.
