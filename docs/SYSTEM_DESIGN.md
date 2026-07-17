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
    App --> Proxy["Reverse proxy HTTPS"]
    Proxy --> SupabaseAuth["Supabase Auth / JWKS"]
    Proxy --> SupabaseDB["PostgREST / synced_accounts + RLS"]
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
5. Local data source serialize mutation, ghi immutable record cùng versioned
   manifest rồi publish commit marker sau cùng.

Local vault v2 fallback về committed generation trước nếu generation mới hỏng.
Lần đọc đầu dual-read legacy index/record, repair dangling ID, recover UUID-keyed
orphan hợp lệ và không xóa legacy key. Xem [ADR-0002](adr/0002-versioned-local-vault-storage.md).

### Tạo mã

`GenerateTotpCode` dùng package `otp`, clock hiện tại và algorithm/digits/period
đã lưu. Countdown tính từ Unix epoch theo period của từng account; code cache theo
time step và được đồng bộ lại khi app resume. Test có thể inject timestamp/clock.

### Cập nhật và xóa

Update/delete publish generation mới; active record/generation cũ không bị sửa
trước commit. Compaction/retention lịch sử vẫn là khoảng trống đã biết.

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

Data source bọc `signInWithPassword`, `signUp`, password recovery/update, `signOut`
và auth-state stream. Remember Me chỉ lưu email cùng trạng thái checkbox trong
SharedPreferences. Supabase login là tùy chọn cho cloud feature; router không dùng
session để chặn local vault. Logout chỉ kết thúc session, không xóa TOTP local hoặc
tắt app lock.

Self-hosted baseline dùng release official đã pin với PostgreSQL 17. Public traffic
đi qua reverse proxy và Kong; session JWT mới ký ES256. Flutter chỉ mang
publishable key, còn service-role/secret key ở server operator boundary.

## Đồng bộ

Sync được kích hoạt thủ công; preference chỉ điều khiển availability trong UI.
Do remote contract còn plaintext, sync bị khóa mặc định. Chỉ build migration/test
có `ALLOW_INSECURE_PLAINTEXT_SYNC=true` mới đi qua cả BLoC và remote data source.

E2EE v2 rollout theo ADR-0005: `VaultCipher` cung cấp AES-256-GCM snapshot/AAD và
DEK wrapping; `VaultKeyStore` giữ DEK per Supabase user; migration tạo một encrypted
snapshot/user cùng RPC optimistic revision. Các primitive chưa nối vào `SyncBloc`
hoặc onboarding UI, nên release sync tiếp tục fail closed.

### Merge

1. Download remote rows.
2. `MergeAccountsUseCase` đọc local accounts và dùng stable `account_id` làm identity.
3. Remote record chưa có được validate/persist với nguyên ID; local record thắng
   trong compatibility bridge khi trùng ID.
4. Nếu persistence lỗi, emit failure và dừng; UI reload chỉ sau commit local.
5. Upload snapshot local sau merge khi dangerous development flag được bật.

Merge không còn điều phối bằng Bloc-to-Bloc stream/completer nên không báo success
trước khi persistence hoàn tất. Revision/conflict/deletion vẫn cần sync-v2 ADR.

### Overwrite/upload

1. Xóa mọi row remote thuộc user.
2. `SupabaseAccountMapper` đổi camelCase local sang snake_case remote.
3. Chèn toàn bộ snapshot.

Thuộc tính chưa an toàn:

- secret ở plaintext;
- thao tác xóa-rồi-chèn không atomic;
- không có tombstone, revision, optimistic concurrency hoặc encrypted-format migration;
- RLS chỉ authorization theo owner, không phải E2EE.

Schema/RLS đã được version hóa trong `supabase/migrations`; force RLS và bốn policy
CRUD dùng `auth.uid() = user_id`. Cross-user contract test chạy qua public API và
dọn isolated user/row sau khi hoàn tất.

Xem [Bảo mật](SECURITY.md), [Tích hợp Supabase](SUPABASE_INTEGRATION.md) và [Thiết kế E2EE](E2EE_DESIGN.md).

## Trang recovery

`reset-password-web` là canonical recovery surface, container Nginx read-only/non-root. Entrypoint validate và
runtime-inject URL/publishable key, response dùng CSP/no-store và frontend không
log session. Flutter gửi `PASSWORD_RECOVERY_URL`; self-hosted template đóng gói
dùng fragment `token_hash`, còn trang gọi `verifyOtp`. Template/allow-list và
email-link E2E chưa deploy nên flow production vẫn chưa hoàn tất.

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
