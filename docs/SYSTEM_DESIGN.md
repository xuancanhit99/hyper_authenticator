# Thiết kế hệ thống

Tài liệu này mô tả runtime đã triển khai. Hạng mục tương lai phải có nhãn
**Dự kiến** hoặc **Khoảng trống đã biết**.

## Bối cảnh và trust boundary

Hyper Authenticator là Flutter client local-first. TOTP secret ở local vault;
Supabase cung cấp Auth và một encrypted snapshot cho mỗi user. Backend chỉ nhận
ciphertext, wrapped DEK và concurrency metadata.

~~~mermaid
flowchart LR
  User["Người dùng"] --> App["Flutter app"]
  App --> Lock["OS local authentication"]
  App --> Vault["Platform secure storage\nversioned local vault"]
  App --> Prefs["SharedPreferences\nkhông chứa secret"]
  App --> Cipher["AES-256-GCM + recovery key"]
  Cipher --> HTTPS["Reverse proxy HTTPS"]
  HTTPS --> Auth["Supabase Auth"]
  HTTPS --> RPC["Atomic revision RPC"]
  RPC --> DB["encrypted_vault_snapshots\nFORCE RLS"]
  Recovery["Recovery Web"] --> Auth
~~~

Web không bật encrypted sync vì browser key storage khác native secure storage.
Web vẫn chạy TOTP local trong storage do platform plugin cung cấp; người dùng phải
hiểu browser profile compromise nằm ngoài native trust boundary.

## Bootstrap

1. Khởi tạo Flutter binding.
2. Injectable/GetIt đăng ký dependency và pre-resolve SharedPreferences.
3. `AppConfig` đọc compile-time define; `.env` không được bundle làm asset.
   Validator chỉ nhận HTTPS Supabase origin cùng `sb_publishable_*` hoặc legacy
   JWT có role `anon`; release bắt buộc recovery URL và plaintext flag tắt.
4. Khởi tạo Supabase client.
5. Cấp shared `AuthBloc`, `AccountsBloc`, `LocalAuthBloc`, `SettingsBloc`; tạo
   `SyncBloc` dùng chính `AccountsBloc` đó.
6. Router kết hợp Auth và local-lock state để chọn public route, startup, lock
   hoặc main navigation.

Thiếu/sai URL hoặc key gây bootstrap error rõ ràng, không fallback tới server
khác. `sb_secret_*` và legacy `service_role` bị từ chối mà không đưa key vào error.

## Kiến trúc feature

- Presentation phát event và render state.
- Domain giữ entity, repository contract, crypto service contract và use case.
- Data source sở hữu secure storage, SharedPreferences và Supabase calls.
- Repository chuyển exception sang typed `Failure` bằng `Either`.
- `injection_container.config.dart` được generate, không sửa thủ công.

## Biên triển khai Web

Flutter Web artifact được phục vụ bởi `web-deployment` qua Nginx non-root. Runtime
entrypoint chỉ nhận public Supabase HTTPS origin để tạo CSP; client key vẫn được
embed lúc Flutter compile theo public-config contract. HTML dùng `no-store`, asset
revalidate, SPA fallback về `index.html`; access log tắt để query material không
vào container log. Reverse proxy bên ngoài sở hữu TLS và domain routing.

GoRouter giữ URL làm source of truth cho main navigation: `/` mở Accounts và
`/settings` mở Settings. Không ép `initialLocation`, vì làm vậy sẽ bỏ qua browser
deep link và platform route ban đầu. Bottom navigation cập nhật URL bằng `go`, còn
router truyền selected index trở lại shell để refresh/back giữ đúng tab.

## Local vault

`AuthenticatorLocalDataSource` serialize mutation bằng critical section:

1. Đọc generation committed hiện tại.
2. Validate toàn bộ account và tạo snapshot mới.
3. Ghi immutable record/manifest của generation mới.
4. Ghi commit marker sau cùng.
5. Đọc lại để verify.
6. Best-effort compaction, giữ hai generation hợp lệ gần nhất.

Nếu generation mới hỏng, reader fallback generation trước. Legacy index/record
được dual-read và repair nhưng không bị xóa ngay, giúp rollback. `replaceAccounts`
dùng cùng transaction copy-on-write và là primitive duy nhất cho cloud recovery.

## TOTP

- Manual entry dùng default SHA1/6 digits/30 giây.
- QR parser giữ algorithm, digits và period không mặc định.
- Account có UUID stable; update/restore không tự đổi ID.
- Code dùng Unix epoch và period của từng account; UI cache theo time step và
  refresh khi app resume.
- Full `otpauth` URI, `secretKey` và generated code không được log.

## App lock và logout

Local-auth preference nằm trong SharedPreferences; OS challenge do `local_auth`.
Khi lock đã bật, plugin error là locked state. App relock khi rời foreground.
Logout chỉ kết thúc Supabase session, giữ local vault và lock preference.

## Encrypted sync

### Setup

1. Xác minh user đã đăng nhập và cloud vault chưa tồn tại.
2. Sinh DEK 256-bit cùng recovery key `HA1-...`.
3. Hiển thị recovery key một lần; user phải xác nhận đã lưu.
4. Encrypt snapshot local revision 1, atomic publish với expected revision 0.
5. Download/read-after-write verify revision và envelope.
6. Chỉ sau đó persist DEK vào secure storage và bật sync metadata.

Cancel hoặc publish failure không persist key và không bật sync.

### Sync thường

1. Download current encrypted snapshot và decrypt/validate trong memory.
2. So sánh remote revision với last-seen revision trên thiết bị.
3. Nếu không conflict và local khác remote, encrypt local ở revision kế tiếp.
4. RPC compare-and-swap theo expected revision.
5. Download lại và verify trước khi cập nhật last-seen revision.

RPC không delete snapshot cũ trước update. Conflict trả typed failure, giữ cả
local snapshot và cloud snapshot hiện có.

### Recovery và conflict

Thiết bị mới nhập recovery key để unwrap DEK. Remote payload phải authenticate,
decrypt và validate hoàn toàn trước khi local write. Nếu local không rỗng và khác
cloud, UI yêu cầu chọn:

- **Dùng cloud:** re-download đúng revision đã review rồi atomic replace local.
- **Giữ local:** encrypt local và compare-and-swap thành revision mới.

Nếu cloud đổi tiếp trong lúc chọn, thao tác dừng và yêu cầu review lại.

## Backend

- Một row `encrypted_vault_snapshots` cho mỗi `auth.users.id`.
- Client authenticated chỉ có SELECT row của chính mình qua `FORCE RLS`.
- Write chỉ qua `SECURITY DEFINER` RPC dùng `auth.uid()`.
- Expected revision sai trả SQLSTATE `PT409`/`revision_conflict`.
- `synced_accounts` plaintext còn là compatibility schema, không nằm trong runtime DI.

## Recovery password

Web recovery là canonical surface. GoTrue template dùng one-time `token_hash` và
exact HTTPS redirect allow-list. Password recovery chỉ khôi phục Supabase account;
nó không thay thế E2EE recovery key.

## Platform capability

`PlatformCapabilities` là source of truth để ẩn camera/image/local-auth/E2EE trên
platform plugin không hỗ trợ. Windows/Linux vẫn hỗ trợ nhập TOTP thủ công và E2EE;
Web chỉ có local TOTP + camera QR.

## Failure behavior

- Decrypt/validation/auth failure: không mutate local vault.
- Local commit failure: generation cũ vẫn active.
- Publish conflict/network failure: cloud snapshot cũ vẫn tồn tại.
- Session đổi giữa operation: request bị từ chối trước network/write kế tiếp.
- Secure key write không verify được: setup/recovery trả failure.

## Khoảng trống đã biết

- E2EE v1 chưa có key rotation, revoke device, tombstone hoặc Web support.
- Device-level camera/biometric/secure-storage integration coverage chưa đầy đủ.
- Alerting backend chưa có external notification channel.
