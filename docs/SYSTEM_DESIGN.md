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
2. Trên Windows, nhập layout AppData từng dùng ở pre-release vào layout
   canonical trước khi bất kỳ secure storage/SharedPreferences nào khởi tạo.
   Hai vault khác nhau làm bootstrap fail closed; nguồn không bị xóa.
3. Injectable/GetIt đăng ký dependency và pre-resolve SharedPreferences.
4. `AppConfig` đọc compile-time define; `.env` không được bundle làm asset.
   Validator chỉ nhận HTTPS Supabase origin cùng `sb_publishable_*` hoặc legacy
   JWT có role `anon`; release bắt buộc recovery URL. Plaintext flag chỉ còn là
   poison sentinel và mọi build đều từ chối giá trị `true`.
5. Khởi tạo Supabase client.
6. Cấp shared `AuthBloc`, `AccountsBloc`, `LocalAuthBloc`, `SettingsBloc`; tạo
   `SyncBloc` dùng chính `AccountsBloc` đó.
7. Router kết hợp Auth và local-lock state để chọn public route, startup, lock
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
`/settings` mở Settings. Hai URL là branch của
`StatefulShellRoute.indexedStack`; mỗi branch có Navigator riêng, giữ state khi
đổi tab và không chạy full-page transition giữa các tab. Page của shell dùng
`NoTransitionPage` có chủ đích: khi app-lock redirect xảy ra liên tiếp trong
lifecycle transition, transition mặc định có thể giữ hai shell có cùng
`GlobalKey` trong tree và làm Flutter fail. Các route bootstrap/lock là overlay
child của shell nhưng render trên root navigator, vì vậy shell luôn mounted và
bottom navigation không lọt qua màn hình khóa. `NavigationBar` vẫn animate
indicator trong 200 ms, còn route phân cấp như Auth hoặc Thêm/Sửa tài khoản tiếp
tục dùng page transition native mà Flutter chọn theo platform.

Không ép `initialLocation`, vì làm vậy sẽ bỏ qua browser deep link và platform
route ban đầu. Bottom navigation dùng `StatefulNavigationShell.goBranch`, nên URL,
refresh và back vẫn chọn đúng tab. Local-auth check thuộc bootstrap/lifecycle và
router redirect, không được phát lại chỉ vì người dùng đổi tab. Web bật
`PathUrlStrategy` qua conditional import; native build dùng no-op stub.

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

Trên Windows, `CompanyName=app.hyperz.authenticator` và
`ProductName=hyper_authenticator` là storage identity canonical từ bản lịch sử
`1.0.0+9`. Tên cửa sổ, installer và `FileDescription` vẫn là “Hyper
Authenticator”. Startup migrator chỉ copy atomic file secure storage/preference
đã allowlist từ layout pre-release `Hyper Authenticator`, giữ nguyên nguồn và ghi
marker sau khi hoàn tất. Nếu cả hai layout chứa vault không byte-identical, app
dừng trước DI để không tự chọn hoặc ghi đè dữ liệu.

## TOTP

- Manual entry dùng default SHA1/6 digits/30 giây.
- QR parser giữ algorithm, digits và period không mặc định.
- Camera scanner render loading state có hướng dẫn permission; lỗi permission hoặc
  unsupported được localize, cho retry hoặc quay lại manual entry. Không hiển thị
  raw plugin error cho người dùng.
- Account có UUID stable; update/restore không tự đổi ID.
- Code dùng Unix epoch và period của từng account; UI cache theo time step và
  refresh khi app resume.
- Full `otpauth` URI, `secretKey` và generated code không được log.

Form thêm account đánh dấu submit đang chạy để chặn request lặp. Sau khi persist,
`AccountsBloc` phát `AccountAddSuccess` không chứa account/secret rồi mới queue
`LoadAccounts`; UI chỉ hoàn tất navigation trên signal operation-specific này.
`AccountsLoaded` do reload/lifecycle không được phép tự đóng route. Khi GoRouter
không còn back stack, completion đi về `/` thay vì gọi `Navigator.pop` trên page
cuối; regression khóa race này qua lifecycle integration Linux.

Form chỉnh sửa dùng cùng contract với `AccountUpdateSuccess`: account đã update
được persist trước khi phát success, state không mang account/secret, nút lưu bị
khóa trong khi request đang chạy và lỗi generic chỉ được render khi form đang
submit. Mỗi submit tạo opaque operation token chỉ tồn tại trong memory; BLoC trả
đúng token trong success và form so sánh identity trước khi đóng, nên update khác
chồng thời gian không thể hoàn tất nhầm route. Failure cũng mang opaque token; chỉ
request tương ứng mới mở lại nút lưu và hiển thị lỗi. Reload danh sách không đóng
form; update ở GoRouter root đi về `/` thay vì pop page cuối. `LoadAccounts` vẫn
được queue sau success để account list nhận dữ liệu mới nhất.

## App lock và logout

Local-auth preference nằm trong SharedPreferences; OS challenge do `local_auth`.
Khi lock đã bật, plugin error là locked state. App relock khi rời foreground.
Logout chỉ kết thúc Supabase session hiện tại, giữ local vault và lock preference.

`PrivacyShield` được đặt trong `MaterialApp.router.builder`, bao toàn bộ router.
Sau bootstrap, mọi lifecycle signal khác `resumed` đều render một surface opaque
không chứa account/user data, bỏ keyboard focus, chặn pointer, dừng ticker và loại
semantics của router. Initial `detached` trước lifecycle signal được xem là trạng
thái bootstrap, vì Linux headless/desktop có thể không phát `resumed`; runtime CI
khóa contract này để app không tự che vĩnh viễn. Khi resume, shield chỉ gỡ overlay;
state/vault không bị tạo lại hoặc mutate. Control này bổ sung cho `LocalAuthBloc`:
privacy shield che ngay ở `inactive`, còn app-lock vẫn quyết định challenge theo
policy hiện tại.

Overlay là Material 3 static, có nền và gradient đã alpha-blend thành màu opaque,
branding cùng biểu tượng khóa nhưng không blur/sample route nhạy cảm bên dưới.
Layout dùng `SafeArea`, giới hạn chiều rộng và co giãn ở viewport 320 px/text scale
200%; light/dark theme đều giữ đúng một semantics label an toàn. Overlay không có
transition, spinner hoặc ticker nên frame che đầu tiên không chờ animation. Đây là
privacy control cho background/app-switcher, không phải active
screenshot-prevention API.

Settings có `SessionSecurityBloc` riêng để revoke mọi Supabase session khác mà
không đưa `AuthBloc` ra khỏi trạng thái authenticated. Action này giữ session,
local vault và DEK của thiết bị hiện tại. Targeted/bulk revoke chỉ thu hồi
Supabase authorization: nó không remote-wipe local vault, không làm target quên
DEK đã giữ và không loại device key khỏi lần xoay vault key kế tiếp.

`DeviceSessionBloc` đăng ký rồi list các phiên chạy client có device registry.
Backend tự bind registry row với JWT `session_id`; client chỉ giữ installation UUID
không phải credential. Targeted revoke cấm current row và xóa đúng target
`auth.sessions`, vì vậy active-session guard chặn cloud access ngay. Local vault
trên target không bị xóa, target có thể đăng nhập lại và session cũ chưa đăng ký
vẫn chỉ xử lý được bằng bulk revoke. Backend có contract loại device key trong
atomic rotation, nhưng Settings/generic rotation hiện chưa cung cấp lựa chọn thiết
bị: client gửi danh sách exclusion rỗng.

## Encrypted sync

### Setup

1. Xác minh user đã đăng nhập và cloud vault chưa tồn tại.
2. Sinh DEK 256-bit cùng recovery key `HA1-...`.
3. Hiển thị recovery key một lần; user phải xác nhận đã lưu. Raw key bị loại khỏi
   semantics tree tự động; assistive user dùng action “Sao chép recovery key” có
   nhãn rõ ràng để chuyển key sang password manager.
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
Dialog conflict và sensitive operation mặc định keyboard focus vào **Hủy**; content
scroll được ở viewport hẹp hoặc text scale lớn. Sync status progress/conflict/
success/failure là live region, còn switch sinh trắc học/encrypted sync gắn trực
tiếp accessible name với title của setting.

Light/dark theme dùng primary/on-primary token riêng để giữ brand blue nhưng đạt
WCAG AA text contrast trên các core surface. Widget regression khóa contract này
ở Auth, account list, form thêm account và sensitive Settings dialog; đây không
thay cho TalkBack/VoiceOver hoặc audit toàn bộ UI trên thiết bị thật.

Core keyboard contract dùng focus tree mặc định của Flutter nhưng khóa thứ tự và
activation bằng Tab/Shift+Tab/Enter/Space. Sensitive dialog mặc định focus
**Hủy**; recovery-key confirmation chỉ cho tới action sau xác nhận đã lưu key và
bắt Escape để trả `false` kể cả khi barrier không dismissible. Contract này chưa
thay full Settings/main-navigation runtime audit trên từng desktop/browser.

### Xoay recovery key

Thiết bị đang giữ DEK có thể tạo KEK mới, re-wrap cùng DEK, re-encrypt current
remote snapshot và compare-and-swap revision kế tiếp. Hủy hoặc conflict giữ key
cũ. User phải lưu key mới trước commit vì nếu publish thành công nhưng
read-after-write lỗi thì key mới có thể đã hiệu lực. Flow này không revoke thiết
bị vì DEK không đổi.

### Xoay vault key

Client tạo DEK và recovery key mới sau khi xác thực DEK hiện tại với current remote
snapshot. Khi user xác nhận đã lưu key, client re-download đúng revision, decrypt
bằng DEK cũ, re-encrypt bằng DEK mới rồi atomic publish ciphertext/wrapped key ở
revision kế tiếp. DEK secure storage chỉ được thay sau read-after-write verify.

Trước khi tạo bất kỳ next-generation wrap nào, client kiểm tra mọi active device
có current-generation wrap đầy đủ và membership proof HMAC hợp lệ với DEK hiện
tại. Một proof thiếu, stale hoặc giả làm toàn bộ preparation fail closed trước khi
tạo wrap/publish. Generic flow sau đó cấp wrap mới cho **tất cả** active device đã
được verify; UI hiện chưa triển khai per-device cryptographic exclusion.

Conflict/cancel không đổi key. Publish transport, verify hoặc key-store failure sau
request được báo là trạng thái mơ hồ và last-seen revision không tăng; recovery key
mới là đường khôi phục. Thiết bị tuân thủ chỉ có DEK cũ không đọc được current
snapshot, nhưng auth session và backup cũ không tự bị revoke.

Surviving native device không thử decrypt mãi bằng DEK cũ rồi yêu cầu HA1. Khi
current snapshot có `device_wrap_version=1`, client đọc exact current-device wrap,
unwrap bằng private key local, verify membership proof và chỉ persist DEK mới sau
khi current snapshot decrypt/validate thành công. Missing private key, không có
wrap do một rotation có exclusion, session binding sai hoặc wrap/proof lỗi đều fail
closed; auth/server failure không bị mô tả sai thành recovery-key failure.

## Backend

- Một row `encrypted_vault_snapshots` cho mỗi `auth.users.id`.
- Client authenticated chỉ có SELECT row của chính mình qua `FORCE RLS` khi JWT
  `session_id` vẫn tồn tại cho cùng `auth.uid()` trong `auth.sessions`.
- Write chỉ qua `SECURITY DEFINER` RPC dùng cùng owner + active-session guard.
- `SignOutScope.others` xóa các session khác; RLS trả 0 row và RPC trả
  `session_revoked` cho JWT cũ ngay cả trước khi JWT hết hạn.
- Device registry chỉ qua security-definer RPC: register bind current JWT, list
  active owned row không lộ session ID và targeted revoke xóa một non-current
  `auth.sessions` row. Installation ID/label không được dùng làm authorization.
- Expected revision sai trả SQLSTATE `PT409`/`revision_conflict`.
- Legacy `publish_encrypted_vault_snapshot` chỉ được tạo revision 1 với
  `expected_revision=0`; mọi update tiếp theo phải dùng device-bound RPC v2.
- RPC v2 khóa exact row/revision/generation bằng `FOR UPDATE`, kiểm tra protocol
  `1` trên row đã khóa rồi mới xác minh active device binding và update. Protocol
  `0` hoặc version stale đều fail trước mutation, đóng cửa sổ TOCTOU khi confirm
  device key chạy đồng thời.
- Plaintext client stack đã bị xóa. Migration loại bỏ cuối cùng lấy
  `ACCESS EXCLUSIVE` lock trước khi đếm và chỉ drop `public.synced_accounts` trong
  nhánh đã lock khi row count bằng `0`; còn credential legacy thì abort nguyên
  transaction và không dùng `CASCADE`. `ALLOW_INSECURE_PLAINTEXT_SYNC` chỉ còn là
  poison sentinel; giá trị `true` bị từ chối ở mọi build.

## Recovery password

Web recovery là canonical surface. GoTrue template dùng one-time `token_hash` và
exact HTTPS redirect allow-list. Password recovery chỉ khôi phục Supabase account;
nó không thay thế E2EE recovery key.

Login được mở từ Settings với `returnTo=/settings`. Redirect policy chỉ nhận `/`
hoặc `/settings`; URL ngoài allowlist fallback `/`. Login listener chủ động `go()`
tới destination này sau `AuthAuthenticated`, không phụ thuộc timing của router
refresh hoặc navigator stack.

## Platform capability

`PlatformCapabilities` là source of truth để ẩn camera/image/local-auth/E2EE trên
platform plugin không hỗ trợ. Windows/Linux vẫn hỗ trợ nhập TOTP thủ công và E2EE;
Web chỉ có local TOTP + camera QR.

## Failure behavior

- Decrypt/validation/auth failure: không mutate local vault.
- Local commit failure: generation cũ vẫn active.
- Publish conflict/network failure: cloud snapshot cũ vẫn tồn tại.
- Session đổi giữa operation: request bị từ chối trước network/write kế tiếp.
- Session đã revoke: RLS không trả snapshot; RPC fail `session_revoked`; local
  vault không bị xóa và session hiện tại không bị sign out.
- Secure key write không verify được: setup/recovery trả failure.

## Khoảng trống đã biết

- E2EE v1 đã có recovery-key re-wrap, DEK rotation và bulk revoke mọi session
  khác. Device registry + targeted auth-session revoke đã deploy. ADR-0012 cùng
  device-wrap client/migration/RPC đã deploy và pass focused, PostgreSQL, remote
  regression cùng Linux/Android/iOS lost-key runtime và two-session survivor
  auto-unwrap. Generic client rotation giữ toàn bộ active device có proof hợp lệ;
  per-device cryptographic exclusion chưa có flow cho người dùng. Physical
  two-device/independent review, tombstone/history và Web E2EE vẫn chưa có.
- Device-level camera/biometric/secure-storage integration coverage chưa đầy đủ.
- Alerting backend chưa có external notification channel.
