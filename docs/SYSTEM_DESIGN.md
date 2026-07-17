# Thiết kế hệ thống

Tài liệu này mô tả implementation hiện tại. Thiết kế E2EE và sync dài hạn được ghi riêng và không được xem là đã triển khai.

## Bối cảnh

Hyper Authenticator là Flutter client đa nền tảng với hai ranh giới persistence:

- storage trên thiết bị cho TOTP và preference;
- Supabase Auth/PostgreSQL cho session và sync thủ công.

Sản phẩm hiện bắt buộc xác thực Supabase trước khi vào UI authenticator.

~~~mermaid
flowchart LR
    User["Người dùng"] --> App["Ứng dụng Flutter"]
    App --> DeviceAuth["Sinh trắc học / credential OS"]
    App --> SecureStorage["FlutterSecureStorage"]
    App --> Preferences["SharedPreferences"]
    App --> SupabaseAuth["Supabase Auth"]
    App --> SupabaseDB["Supabase synced_accounts"]
    Recovery["Trang recovery tĩnh"] --> SupabaseAuth
~~~

## Bootstrap

1. Khởi tạo Flutter binding.
2. Đăng ký Injectable/GetIt và pre-resolve SharedPreferences.
3. `AppConfig` đọc `SUPABASE_URL` và `SUPABASE_PUBLISHABLE_KEY` từ compile-time environment; `SUPABASE_ANON_KEY` chỉ là fallback cũ.
4. Khởi tạo Supabase.
5. Cấp shared instance `AuthBloc`, `AccountsBloc`, `LocalAuthBloc`, `SettingsBloc` và `SyncBloc` vào widget tree.
6. Auth/local-lock state khởi tạo.
7. GoRouter chọn login, startup, lock hoặc main navigation.

Thiếu Supabase configuration sẽ hiển thị bootstrap error. `.env` không được load hoặc đóng gói ở runtime; lệnh chạy dùng `--dart-define-from-file=.env`.

## Điều hướng

| Route | Mục đích | Quyền truy cập |
|---|---|---|
| `/login` | Đăng nhập | Công khai |
| `/register` | Đăng ký | Công khai |
| `/forgot-password` | Yêu cầu recovery email | Công khai |
| `/update-password` | Đặt mật khẩu mới | Public route; deep-link flow chưa hoàn thiện |
| `/` | Accounts và Settings | Đã xác thực, đã qua app lock |
| `/add-account` | Thêm TOTP | Đã xác thực, đã qua app lock |
| `/edit-account` | Sửa account từ route state | Đã xác thực, đã qua app lock |
| `/lock-screen` | Challenge credential thiết bị | Đã xác thực và đang bị khóa |

Router refresh từ `AuthBloc` và `LocalAuthBloc`. Trạng thái local-auth lỗi được xem là bị khóa (fail closed); startup state không hiển thị nội dung được bảo vệ trước khi auth hoàn tất.

## Kiến trúc Flutter

    lib/
      core/
        config/
        platform/
        router/
      features/
        auth/
        authenticator/
        main_navigation/
        settings/
        sync/

Mỗi feature chủ yếu gồm:

- **Presentation:** page, widget, event/state và BLoC.
- **Domain:** entity, repository contract, service và use case.
- **Data:** implementation Supabase/local storage.

GetIt/Injectable quản lý dependency, BLoC quản lý feature state, Provider quản lý theme và fpdart `Either` truyền failure qua domain boundary. `AuthBloc` và `AccountsBloc` là lazy singleton; provider dùng `BlocProvider.value` nên UI và sync quan sát cùng instance.

## Luồng TOTP

### Nhập và lưu

1. `AddAccountPage` nhận input thủ công, barcode camera hoặc ảnh trên platform hỗ trợ.
2. `TotpUriParser` chỉ chấp nhận `otpauth://totp`, parse label/issuer và validate Base32, SHA1/SHA256/SHA512, digits 6–8, period dương.
3. `AccountsBloc` gọi use case add.
4. Local data source gán UUID nhưng giữ toàn bộ tham số TOTP.
5. JSON được ghi vào secure storage, sau đó UUID được ghi vào index.

Record và index vẫn là hai thao tác không transactional; recovery khi partial write là việc còn mở.

### Tạo mã

`GenerateTotpCode` dùng package `otp`, clock hiện tại và algorithm/digits/period đã lưu. Test có thể inject timestamp để chạy deterministic. UI refresh mỗi giây.

Khoảng trống: countdown widget hiện dùng chu kỳ 30 giây thay vì period của từng account.

### Cập nhật và xóa

Update ghi đè JSON cùng ID. Delete xóa record rồi cập nhật index. Không có transaction cho hai bước này.

## Khả năng theo platform

`PlatformCapabilities` giữ policy tập trung:

| Capability | Android | iOS | macOS | Windows | Linux | Web |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Camera QR | Có | Có | Có | Không | Không | Có |
| Phân tích ảnh QR | Có | Có | Có | Không | Không | Không |
| Local authentication | Có | Có | Có | Có | Không | Không |
| Nhập TOTP thủ công | Có | Có | Có | Có | Có | Có |

UI không hiển thị action plugin không hỗ trợ. Capability này phản ánh package/API hiện tại, không phải cam kết release-readiness.

## Khóa thiết bị

Preference `biometric_enabled` lưu trong SharedPreferences.

- `local_auth` cho phép biometrics hoặc credential của OS.
- Không dùng PIN riêng của ứng dụng.
- Authentication có thể tiếp tục qua background transition do plugin quản lý.
- Khi app hidden/paused/detached, BLoC reset và router khóa lại.
- Unsupported platform bỏ qua feature; lỗi trên platform đã bật khóa thì fail closed.

Đây là UI gate, không phải encryption cho từng record.

## Supabase authentication

Data source bọc `signInWithPassword`, `signUp`, password recovery/update, `signOut` và auth-state stream. Remember Me chỉ lưu email cùng trạng thái checkbox trong SharedPreferences. Logout chỉ kết thúc session; không xóa TOTP local.

## Đồng bộ

Sync được kích hoạt thủ công; preference chỉ điều khiển availability trong UI.

### Merge

1. Download remote rows.
2. Đọc local accounts.
3. Tạo identity key từ issuer và account name viết thường.
4. Thêm remote record chưa có ở local; không resolve field conflict.
5. Nếu merge lỗi, emit failure và dừng.
6. Upload snapshot local sau merge.

### Overwrite/upload

1. Xóa mọi row remote thuộc user.
2. Chèn toàn bộ snapshot.

Thuộc tính chưa an toàn:

- secret ở plaintext;
- thao tác xóa-rồi-chèn không atomic;
- không có tombstone, revision, optimistic concurrency hoặc migration;
- schema/RLS không được track trong repository.

Xem [Bảo mật](SECURITY.md), [Tích hợp Supabase](SUPABASE_INTEGRATION.md) và [Thiết kế E2EE](E2EE_DESIGN.md).

## Trang recovery

`reset-password-web` là HTML/CSS/JavaScript tĩnh gọi Supabase Auth. Cấu hình URL/key vẫn để trống và Docker/Compose chưa inject được public config, nên chưa là artifact có thể deploy.

## Platform build

- Android: Gradle/AGP/Kotlin hiện đại, JVM 17.
- iOS/macOS: Swift Package Manager hoàn toàn, không CocoaPods.
- Web: release build đã xác minh.
- Windows/Linux: native CI build; manual entry là fallback khi scanner/local-auth không có.

Chi tiết xác minh và release gate nằm trong `PROJECT_STATUS.md` và `DEPLOYMENT.md`.

## Bản đồ tác động thay đổi

- Persisted field: entity JSON, round-trip test, migration, remote contract và `DATA_MODELS.md`.
- Auth/route: redirect test và tài liệu này.
- Sync: ADR, conflict semantic, `SECURITY.md`, `SUPABASE_INTEGRATION.md` và destructive-path test.
- Plugin/platform: capability, permission/entitlement, CI và `DEPLOYMENT.md`.
- Encryption: ADR, format version, recovery/migration và cryptographic test.
