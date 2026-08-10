# Thiết kế hệ thống

Tài liệu này mô tả source runtime sau ADR-0020. Trạng thái deploy nằm trong
[PROJECT_STATUS.md](PROJECT_STATUS.md).

## Mục tiêu

- TOTP local luôn hoạt động không cần tài khoản/network.
- Đăng nhập thì đồng bộ tự động, thiết bị mới không cần recovery key.
- Local mutation không bị rollback vì cloud lỗi.
- Không log/persist TOTP plaintext ngoài local vault và backend RPC boundary.
- UI phát event/render state; persistence/network thuộc data/repository layer.

## Component

```text
Flutter UI
  ├── Accounts / Auth / Settings
  ├── AccountsBloc / AuthBloc / global SyncBloc
  └── GoRouter + lifecycle/privacy shield
        │
Domain
  ├── TOTP parser/validator/generator/import/export
  ├── AuthenticatorRepository
  └── AccountSynchronizer
        │
Data
  ├── FlutterSecureStorage local vault v2
  ├── secure ownership/revision/fingerprint metadata
  └── Supabase Auth + Vault-backed authenticated RPC
```

GetIt/Injectable quản lý dependency. `injection_container.config.dart` là output
generated, không sửa thủ công.

## Chrome Extension foundation

`lib/main_extension.dart` là entrypoint riêng cho Manifest V3 Side Panel. Nó
tái dùng TOTP domain, Accounts/Auth/Sync BLoC và Supabase RPC nhưng không import
primary `AppRouter`/mobile scanner. Vì vậy package MVP chỉ có list/search/copy,
manual add/edit/delete, Settings và account sync; không có QR scanner/import
hoặc protected QR export.

`SecureKeyValueStore` tách feature storage khỏi plugin:

- native/hosted Web giữ `FlutterSecureStorage` adapter hiện có;
- Chrome Extension compile-time flag dùng bridge `chrome_extension/vault.js`;
- bridge giữ AES-256-GCM `CryptoKey` non-extractable trong IndexedDB và record
  ciphertext riêng; local vault v2 và sync metadata không đổi serialization;
- Supabase session/PKCE storage extension dùng cùng vault namespace, không dùng
  `localStorage`.
- CanvasKit extension bundle kèm Roboto trong FontManifest và đúng Noto Sans
  WOFF2 fallback mà engine có thể yêu cầu; bootstrap ép fallback vào path
  self-hosted, không dựa vào Google Fonts dù có glyph thiếu.

Extension local vault không chia sẻ trực tiếp với website/native storage. Sau
login, account-managed sync là đường chia sẻ duy nhất. Side Panel chạy countdown
và foreground sync; MV3 service worker chỉ mở panel, không chứa credential/timer.

Trạng thái: foundation source/package đã có; Chrome profile runtime/store
evidence chưa có, xem ADR-0022 và `tasks/2026-08-chrome-extension.md`.

## Bootstrap

`AppConfig` đọc compile-time public config:

- thiếu toàn bộ cloud config: app bootstrap local-only;
- cloud-enabled cần HTTPS `SUPABASE_URL`, publishable key và HTTPS
  `PASSWORD_RECOVERY_URL`;
- service-role/database/Vault root key không thuộc Flutter build.

## Local vault

`AuthenticatorLocalDataSource` dùng versioned copy-on-write snapshot:

1. đọc committed generation mới nhất validate được;
2. ghi/verify generation mới;
3. publish commit marker;
4. giữ generation rollback gần nhất và compact bản cũ.

Add/update/delete/import/replace serialize trong process. Logout không xóa vault.

## Account-managed sync

### Remote boundary

- `CloudAccountRepository`: list/upsert/delete per-account record.
- Supabase RPC kiểm tra `auth.uid()` và là đường duy nhất client dùng.
- Payload account được Supabase Vault authenticated-encrypt khi lưu. Table/backup
  không giữ payload plaintext; RPC có thể decrypt cho đúng owner.
- Revision CAS cô lập concurrent mutation. Tombstone không thể revive.

Đây là encryption at rest do server quản lý, không phải E2EE.

### Metadata local

Secure storage giữ map theo stable account UUID:

- `ownerUserId`;
- `remoteRevision`;
- `syncedFingerprint`;
- `isDeleted`.

Fingerprint được tính trên canonical account JSON, không đưa plaintext secret vào
log. Metadata corrupt/write-verify fail làm sync dừng fail-safe.

### Trình tự sync

1. Nếu chưa đăng nhập, trả `signedOut` và không gọi network.
2. Đọc local vault + metadata.
3. Bind mọi account chưa có owner với user hiện hành và verify metadata **trước
   network**.
4. List toàn bộ remote record của user.
5. Áp tombstone trước; tombstone thắng local dirty update.
6. Tải live record về nếu local chưa có hoặc local đang clean.
7. Upload local create/update dirty bằng CAS; conflict refresh rồi retry một lần.
8. Local record đã mất nhưng metadata còn live được publish thành tombstone.
9. Verify/persist metadata; lỗi giữ pending intent cho lần sau.

Account thuộc user khác bị bỏ qua trong phiên hiện hành và vẫn dùng local.

### Trigger

Global `SyncBloc` tự yêu cầu sync khi:

- session restore/sign-in;
- add/update/import/delete thành công;
- app resume;
- người dùng pull-to-refresh hoặc bấm retry trong Settings.
- private Realtime channel của user báo cloud đã thay đổi hoặc reconnect.

Realtime event được debounce 350 ms rồi gọi cùng full sync; message không chứa
account data. Sync events được serialize. Download/delete remote thành công yêu
cầu `AccountsBloc` reload list.

### Private Realtime signal

- Topic: `account-sync:<auth.uid()>`, channel bắt buộc `private=true`.
- Database trigger chỉ phát event `account-sync-changed` với protocol version và
  Realtime-generated ID; không phát row/account/Vault data.
- `realtime.messages` chỉ có own-topic `SELECT` policy cho `authenticated`; không
  có client `INSERT` policy.
- Policy chỉ dựa trên extension/topic/`auth.uid()`: Realtime 2.102.3 dùng probe
  row không populate `private`. Channel config vẫn bắt buộc `private=true` và
  trigger luôn gọi `realtime.send(..., true)`.
- Logout/account switch hủy subscription cũ. Channel error không biến RPC sync
  thành failure; reconnect/resume chạy full sync để bù event có thể mất.
- Không thêm `authenticator_accounts` vào Postgres Changes publication.

## Auth và Settings

- Auth hỗ trợ login/register/password recovery/update/session restore.
- Settings hiển thị local-only khi chưa cấu hình hoặc chưa đăng nhập.
- Đăng nhập bật sync tự động; không có setup recovery key/manual backup/conflict
  dialog.
- Logout chỉ kết thúc Supabase session, dừng sync và giữ local/app lock.
- Copy hướng tới người dùng gọi record là “mã xác thực”, issuer là “dịch vụ” và
  Base32 secret là “khóa thiết lập”; tên Supabase, storage và exception không
  thuộc presentation contract.

## Portability

- Standard `otpauth`: bounded parse, preview, validate-all, exact dedupe, atomic
  append; protected export một QR/account.
- Google migration QR: bounded multi-part assembly, preview và atomic append;
  export chỉ nhận semantics Google biểu diễn được.
- Presentation gọi hai đích xuất là “Google Authenticator” và “Ứng dụng khác”;
  chi tiết protocol (`otpauth`, algorithm, digits, period) không xuất hiện trong
  luồng chính. Edit vẫn cho sửa tham số TOTP trong “Tùy chọn nâng cao” thu gọn.
- Import preview chỉ hiện dịch vụ/tài khoản, luôn giữ khóa thiết lập ngoài
  widget tree và chỉ commit sau xác nhận. Export giữ fresh OS auth, QR expiry và
  xóa QR khi ứng dụng ra nền dù copy đã được rút gọn.

## Navigation, theme và privacy

- `StatefulShellRoute.indexedStack` giữ Accounts/Settings branch state.
  Startup/App Lock render trên root navigator nhưng vẫn thuộc Accounts branch
  để shell không bị hủy trong lifecycle redirect. Khi người dùng chọn tab
  Accounts, shell luôn mở initial location `/` thay vì restore một `/startup`
  hoặc `/lock-screen` cũ có `returnTo=/settings`; nếu không redirect thành công
  sau resume có thể đưa người dùng ngược lại Settings. State widget của trang
  Accounts vẫn được indexed stack giữ lại và có regression test.
- Theme có ba style persisted độc lập với ThemeMode. Settings hiển thị chúng
  bằng nhãn Mặc định, OLED và Indigo trong một bottom sheet có preview; enum
  name `securityMinimal`, `oledDark`, `darkCinema` được giữ ổn định để không
  làm mất lựa chọn đã lưu. Theme áp dụng ngay, không có nút lưu. Các bottom
  sheet cấp ứng dụng trong Settings được đặt trên root navigator, không trở
  thành history của riêng Settings branch hoặc lẫn vào state restoration của
  branch khi đổi theme và qua lifecycle transition.
- Preview style tách lớp border ngoài khỏi lớp clip nội dung để viền bo tròn
  luôn kín. Choice chip của chế độ hiển thị dùng icon riêng và tắt checkmark
  mặc định; trạng thái chọn vẫn được biểu đạt bằng màu nền, viền và semantics.
- Settings là entry point duy nhất để đổi style/mode; Accounts AppBar dành cho
  thao tác mã xác thực và không lặp lại quick theme action.
- `AppStylePalette` là nguồn visual token cho màu và geometry. Card, ba loại
  button, TextField, dialog và bottom sheet lấy radius từ palette; TextField
  không dùng pill radius riêng. Card tự clip ripple, không có surface tint và
  layout bên ngoài sở hữu margin.
- App chỉ phát hành locale tiếng Việt. `AppCopy` giữ tên sản phẩm và thuật ngữ
  lặp lại giữa app chính/Chrome Extension; câu theo ngữ cảnh vẫn nằm gần widget.
  `AppMetadata` hiển thị version trong Giới thiệu và có test khóa cả UI metadata
  lẫn Chrome Extension manifest với version canonical trong `pubspec.yaml`.
- App Lock fail closed trên error/cancel.
- Privacy Shield chặn interaction/semantics ngoài foreground nhưng không ngăn OS
  screenshot/recording.

## Provider logo catalog

`ProviderLogoCatalog` load mapping và inventory asset local trước `runApp` cho cả
ứng dụng chính lẫn Chrome Extension. Resolver chuẩn hóa issuer theo exact value,
biến thể bỏ `.com` và first-word fallback; lookup không gửi request mạng hoặc ghi
log issuer. Mapping chỉ quyết định presentation:

- match hợp lệ: `AccountAvatar` render PNG trong clip tròn;
- issuer/mapping/asset không hợp lệ: render avatar ký tự hoặc shield;
- catalog bootstrap lỗi: toàn bộ app tiếp tục bằng fallback, local TOTP không bị
  chặn.

Snapshot Sentinel Icons, source commit, MIT License, checksum và local typo
override nằm trong `third_party/sentinel-icons` theo ADR-0023. Logo không phải
persisted field và dialog chọn logo cũ không được khôi phục.

## Failure behavior

- `userFacingFailureMessage` là boundary chung từ typed `Failure` sang UI. Chỉ
  `ValidationFailure` do ứng dụng kiểm soát được giữ hướng dẫn chi tiết; lỗi
  server/storage/network dùng copy cố định theo thao tác và không render raw
  `Failure.message`.
- Cloud lỗi: local mutation vẫn thành công; sync báo retry được.
- Metadata ownership lỗi: dừng trước network để tránh cross-account upload.
- Remote payload sai format: không ghi đè local.
- CAS conflict: refresh/retry một lần, sau đó giữ pending.
- Tombstone: luôn thắng update offline; xóa local idempotent.
- Xác nhận xóa nói rõ mã bị xóa trên thiết bị hiện tại và, khi đang đồng bộ,
  được áp tới thiết bị khác.
- Không log TOTP secret, payload, full `otpauth`, auth credential hay Vault key.

## Chưa triển khai

- Background periodic sync hoặc push khi OS suspend app.
- Ownership transfer/account switch UI.
- Tombstone retention/compaction.
- Remote wipe local vault trên thiết bị đã đăng xuất.
