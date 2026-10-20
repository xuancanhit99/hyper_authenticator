# Task: Đăng nhập và đăng ký bằng Google

- Trạng thái: Đã triển khai Web; native/extension acceptance có giới hạn bên dưới
- Bắt đầu: 2026-10-21
- Owner: Project owner / Codex
- Issue hoặc ADR liên quan: ADR-0025

## Mục tiêu

Thêm Google trên Login/Register, cấu hình Supabase production, build/deploy và
kiểm chứng authorize/callback mà không chạm dữ liệu vault thật.

## Ngoài phạm vi

- Không tự xác nhận Google consent thay owner hoặc tạo credential Google mới.
- Không thay identity/vault/schema và các P1/P2 có sẵn.

## Acceptance criteria

- [x] UI Login/Register có nút Google, loading/cancel/error/retry.
- [x] Auth chỉ authenticated từ verified session; callback/PKCE được kiểm chứng.
- [x] Provider server enabled, callback Google đúng, allowlist additive.
- [x] Web deploy, Android/Windows/Linux/extension build; Apple không có toolchain.
- [x] Test/docs/evidence, Google secret không vào runtime artifact.

## Bằng chứng hiện tại

Google JSON Web client owner cung cấp ngoài repo, có đúng origin/callback.
Server đã enable Google. Supabase 2.16.0 mặc định PKCE; native/extension
đã có secure session/verifier storage. Password/local vault giữ nguyên.

## Đánh giá rủi ro

- Credential: server-only secret; private backup, no raw URLs/tokens in logs.
- Local/cloud: không clear/rebind/merge; login dùng ownership hiện hành.
- Migration: không schema migration; native callback và extension identity mới.
- Rollback: provider/env/compose snapshot, không xóa users hoặc downgrade vault v3.
- Platform: mobile app links, desktop ephemeral loopback, extension identity.

## Kế hoạch

- [x] Implement/verify app, provider config và rollout.
- [x] Owner trả lời “Đăng nhập thành công” trên production Web ngày 21-10-2026.
- [x] Chốt evidence, docs và giới hạn.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Auth/router/config suite | 60 pass trước version bump | 2026-10-21 |
| Toàn bộ `flutter test --no-pub` Windows | 328 pass, 6 skip | 2026-10-21 |
| Toàn bộ `flutter test` Linux WSL isolated source | 334 pass | 2026-10-21 |
| `dart analyze lib test integration_test tool` Linux | No issues found | 2026-10-21 |
| Scoped auth analyzer; docs/platform/scoped format | Pass | 2026-10-21 |
| `node --test tool/agent/extension_oauth_test.mjs` | 3 pass; release harness gọi test này | 2026-10-21 |
| Web/extension/Windows/Android/Linux release builds, Debian | Pass | 2026-10-21 |
| Extension package verifier | Pass local executable/fonts/CanvasKit/CSP/identity contract | 2026-10-21 |
| Real Web Chromium | Google sign-in/chooser, không invalid-client/redirect error | 2026-10-21 |
| Owner production Google login | Thành công theo xác nhận trực tiếp trong chat | 2026-10-21 |
| Real isolated extension Chromium | Bridge có thật, Google window mở, đóng/hủy được | 2026-10-21 |
| Android physical install -r / version / callback resolution / launch | Pass 1.1.5 (19), signer pin khớp, không clear vault | 2026-10-21 |
| Windows release window launch/close | Pass | 2026-10-21 |
| Provider settings + 4 callback-class authorize probes | Google/signup enabled, redirect tới Google đúng callback | 2026-10-21 |
| Shadow/public Web serving contract/checksum | Pass routes/CSP/no-store/dotfile denial | 2026-10-21 |
| Signer / artifact Google Client Secret scan | Pass APK contents/Web/extension/Windows/Linux tar | 2026-10-21 |

Evidence ignored tại `build/google-oauth-20261021/`. Unit/widget regression bao
gồm launch-versus-session, callback race, retry/double-click, stream error,
callback exact-match, loopback reject/timeout/close, 200% text và keyboard order.

`scripts/agent/check.sh full` đã chạy nhưng **không pass** trên Windows: thiếu
`shasum`, build_runner output drive C (`No assets exist in C`), whole-repo analyzer
treo (đã dừng; isolated Linux analyzer pass), Docker Desktop engine không chạy,
POSIX mode/symlink fixtures không hợp Windows và checksum fixture CRLF. Lần full
gate gặp native-assets file race khi native build đồng thời; chạy lại test riêng
sau build đã pass toàn suite. Không coi shell wrapper/scoped checks là full-CI pass.

Linux suite lần đầu có 1 failure do test giới thiệu hardcode 1.1.3 (17); sửa theo
version mới và toàn suite chạy lại 334 pass. Thay đổi sau final runtime build chỉ
là tests/harness/docs/provenance.

## Thay đổi và server rollout

Auth repository/data source thêm Google; platform adapters tại
`lib/features/auth/data/oauth`. AuthBloc xử lý pending/callback race/sanitized
stream error. Login/Register dùng shared Google button. Android/iOS callback,
macOS loopback entitlement, extension `identity`/`oauth.js`, builder/verifier và
release harness được cập nhật. Version pubspec/AppMetadata/extension đồng nhất.
Không đổi SQL schema, vault v3, user ownership hay remote sync; không tự merge vault.

Chỉ recreate Supabase `auth`. `.env` mode 0600 giữ Google Secret; compose dùng env
reference. Private snapshot trước cấu hình nằm trong directory mode 0700
`/home/xuancanhit/hyper-google-oauth-20261021` (env/compose mode 0600). JSON upload
tạm đã xóa; operator backup ngoài repo tại
`C:/Users/daota/Backups/hyper_authenticator/google-oauth-client.json`.
Site/recovery URL giữ nguyên, redirect allowlist bổ sung Web/mobile/loopback và
extension `gphicekfcbikgemholbnhcpgneegmjhb`.

Web **1.1.5+19**, image `hyper-authenticator-web:1.1.5-google-20261021`, JS SHA256
`d6dcf93301aa3aa0645b02979276c5829e1a9e131a504060b56309790137afa0`.
Shadow loopback pass trước switch; private compose snapshot
`/opt/stacks/hyper-authenticator/compose.pre-google-20261021.json` giữ image trước
`1.1.4-p1-20261021r2` hiểu vault v3. Rollback UI/provider không xóa Google users,
identity hoặc TOTP; không downgrade writer về vault v2.

## Tác động tài liệu

- [x] PROJECT_STATUS/SUPABASE_INTEGRATION/SECURITY/DEPLOYMENT/SYSTEM_DESIGN
- [x] DEVELOPMENT/TESTING_STRATEGY/ARCHITECTURAL_DECISIONS/ADR-0025

## Bàn giao

Năm artifact tại `build/google-oauth-20261021/artifacts/`: Android signed APK,
Windows portable Preview ZIP, Linux tar.gz/Debian Preview và extension ZIP. Có
SHA256SUMS và artifact-manifest.json ghi base commit, working-tree provenance,
signer và Web hash. Không push/commit hoặc tạo GitHub/store release. Các thay đổi
P1/P2 có sẵn trong working tree được bảo toàn.

Web Google login có owner acceptance. Native/extension chưa kiểm chứng Google
session/consent end-to-end; Android mới có install/launch/callback resolution,
không chứng minh nội dung vault/Keystore round-trip. Apple chưa build. Windows/
Linux unsigned Preview; Linux build Ubuntu 24.04 yêu cầu glibc >=2.38. Desktop
đóng browser mà không callback sẽ timeout sau 3 phút; mobile cần cold/warm lifecycle
acceptance. Google Cloud Audience/Test users/Publishing do owner quản lý.

Unpacked extension ID phụ thuộc đường dẫn/máy; ZIP chuyển chỗ hoặc Chrome Store
ID khác cần operator thêm đúng `https://<id>.chromiumapp.org/auth/callback` vào
server. Không wildcard mọi extension. Không cần gửi thêm credential trong chat.
