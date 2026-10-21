# Bảo mật

## Tài sản cần bảo vệ

Google OAuth dùng external browser và Supabase PKCE. Secret chỉ ở server; app
giữ verifier theo native/extension/browser storage boundary hiện hành. Desktop
listener chỉ bind loopback, random port/path, timeout và exact callback validation;
extension chỉ mở authorize origin/provider/redirect đã pin. Không đưa raw callback,
code hay provider error lên UI. Xem [ADR-0025](adr/0025-google-oauth-pkce.md).

- TOTP `secretKey`, full `otpauth` URI và local vault plaintext.
- Payload account trong lúc authenticated RPC decrypt.
- Supabase session/password-reset token.
- Service-role, DB/JWT/Vault root key, SSH và release-signing credential.

Issuer/account name có thể là dữ liệu cá nhân. Không đưa các giá trị trên vào
log, analytics, issue, screenshot fixture hoặc crash message.

## Trust boundary

### Thiết bị

Local vault và sync ownership metadata nằm trong platform secure storage. App
Lock giảm rủi ro người khác mở app nhưng không chống compromised/rooted OS hoặc
administrator của máy. Privacy Shield che UI ngoài foreground nhưng không phải
OS screenshot/recording prevention.

### Supabase/backend

ADR-0020 chấp nhận server-managed encryption để thiết bị mới chỉ đăng nhập là
tải được mã. Supabase Vault mã hóa/authenticate payload trên disk/backup; RPC có
thể decrypt payload cho đúng `auth.uid()`.

Hệ quả bắt buộc: đây **không phải E2EE/zero-knowledge**. Database superuser,
Vault root-key holder hoặc backend bị chiếm quyền có thể lấy TOTP plaintext.
Operator access, host hardening, backup/key custody và audit phải coi đây là
credential system.

### Web

Web dùng cùng account-sync RPC. Browser profile, origin/XSS và implementation của
`flutter_secure_storage` là trust boundary local; không khẳng định tương đương
Keychain/Keystore native.

### Chrome Extension (GitHub Preview có known runtime gaps)

Manifest V3 Side Panel không xin quyền đọc tab/page/cookie, không có content
script hay autofill. Package verifier chặn remote JS/WASM, ZXing CDN và PWA
service worker; Flutter engine/WASM, Roboto, catalog fallback WOFF2 + OFL đã pin
checksum cùng bridge vault đều ở trong ZIP. Build có thể tải font từ hai origin
allowlist nhưng chỉ nhận đúng URL/SHA-256 trong lock; runtime không tải font/code
từ Internet và CSP không được nới.

Extension vault dùng IndexedDB/WebCrypto AES-256-GCM, nonce mới 96-bit/AAD theo
logical key và `CryptoKey` non-extractable. Supabase session + PKCE cũng đi qua
vault này. Đây giảm nguy cơ ciphertext/key được lưu cùng localStorage, nhưng
**không** tạo Keychain/Keystore hoặc E2EE: browser profile, extension code đã
cài, extension-origin XSS, malware/compromised OS và plaintext trong running
process vẫn là trust boundary. Không có fresh OS auth nên extension MVP không
hiển thị protected QR export.

## Control đã triển khai

Theo ADR-0024, v3 manifest giữ account và owner/delete intent cùng generation;
network result stale không publish qua CAS. Extension init key dùng IDB atomic
transaction, mutation có Web Locks qua contexts, missing key giữ ciphertext và
báo lỗi. Browser/extension code đang chạy vẫn có thể đọc plaintext.

Native session/PKCE không còn nằm trong SharedPreferences sau migration thành
công. Secure write được đọc verify trước khi xóa bản cũ; logout tombstone chặn
legacy restore sau interruption. Migration chưa hoàn tất có thể còn plaintext
cũ để bảo toàn session; app dừng nếu không verify/cleanup được.

Android secure storage giữ namespace/cipher và tắt reset-on-error. Bản vendor
abort corrupt backup entry, verify target và dùng verified migration state để
resume cleanup. Crypto error không được biến thành kho rỗng. Keystore key mất
vẫn không thể tái tạo chỉ từ ciphertext; cần backup độc lập. Configured app lock
giữ locked khi support/plugin mất, và auth result trước background reset không
thể mở khóa trở lại. Physical-device acceptance vẫn tách khỏi unit checks.

### Local và disclosure

- Local vault versioned copy-on-write, serialized mutation và rollback
  generation hợp lệ.
- Secret field che mặc định; protected QR export cần fresh OS auth, có timeout và
  lifecycle cleanup.
- Entity/event/state nhạy cảm redacted trong `toString`.
- Presentation boundary không hiển thị raw exception hoặc message từ
  Supabase/storage/network. Validation local đã kiểm soát mới được giữ copy chi
  tiết để hướng dẫn sửa input.
- Logout giữ local vault.
- Password không trim/normalize ở login/register/reset/update; chỉ email trim.
- Base32 được kiểm byte giải mã/canonical padding/pad bits trước sinh mã; không
  dùng empty/truncated key khi record legacy lỗi. Không tự sửa key đã lưu.
- Clipboard feedback chờ API hoàn tất; lỗi không đưa code/exception vào thông báo.

### Account sync

- Ownership metadata persist + re-read verify trước network call đầu.
- Account thuộc user A không tự upload sang user B.
- Per-account revision CAS; stale mutation refresh/retry tối đa một lần.
- Tombstone thắng update offline và không thể revive qua RPC.
- Cloud failure không rollback local; pending intent retry ở lần sync sau.
- Remote payload được validate/bounded trước lưu và validate lại khi parse client.
- Admission và sync dùng cùng bounds Unicode/JSON với RPC. Live remote payload
  lỗi được cô lập chỉ bằng metadata; giữ cloud/local nguyên trạng và báo partial,
  không tạo deletion intent. Metadata/tombstone sai vẫn dừng toàn bộ chu kỳ.
- Corrupt metadata/payload fail closed, không reset ownership âm thầm.
- Private Realtime chỉ gửi version/generated ID trên own-user topic; không gửi
  account ID, revision, issuer/name, Vault reference hoặc TOTP payload.
- Client không có Broadcast `INSERT` policy; account table vẫn không direct
  `SELECT` và không nằm trong Postgres Changes publication.
- RLS receive không kiểm tra nullable `messages.private` vì Realtime authorize
  bằng probe row chỉ có topic/extension; private join và backend
  `realtime.send(..., true)` là hai enforcement point tương ứng.
- Realtime mất message/error không mutate data; reconnect/resume gọi full RPC
  sync làm fallback.

### Supabase authorization/Vault

- Table bật RLS + FORCE RLS nhưng `authenticated`/`anon` không có direct table
  privilege.
- Ba security-definer RPC tự lấy `auth.uid()`, fixed `search_path`, validate input
  và chỉ truy cập row của user hiện hành.
- Live payload chỉ nằm trong `vault.secrets` ciphertext; tombstone xóa Vault
  secret. Auth-user cascade trigger cũng dọn Vault secret.
- `anon` không có RPC execute; client chỉ có publishable key.
- Vault root key không nằm trong database dump cùng ciphertext và phải được backup
  riêng cùng stack config theo runbook.

### Runtime config

- HTTPS-only Supabase/recovery URL.
- Chỉ nhận publishable/legacy anon key.
- Partial config hoặc service-role-looking config fail release validation.
- `.env`, `.env.server`, signing/key material ignored và không vào artifact.

### Provider logo asset

- Logo provider được bundle local từ snapshot Sentinel Icons đã pin; runtime
  không tải ảnh, không gửi issuer cho CDN/dịch vụ thứ ba.
- Source commit, MIT License, mapping hash và checksum từng PNG được theo dõi;
  LicensePage hiển thị entry `sentinel-icons`.
- Logo/trademark thuộc chủ sở hữu tương ứng và chỉ dùng để nhận diện dịch vụ,
  không ngụ ý liên kết/chứng thực. Update phải review contribution provenance và
  trademark-purpose; khi có khiếu nại có thể xóa asset mà không chạm TOTP data.
- Hai mapping upstream chưa có asset (`bingotp`, `wppokta`) fail-safe về avatar
  ký tự thay vì fuzzy-match sang logo có thể sai.

## Repository security scanning

**Đã triển khai cấu hình:** `.github/workflows/security.yml` dùng CodeQL
security-extended cho Actions, JavaScript/TypeScript (extension/recovery) và
Python (operator tooling), cùng OSV-Scanner quét đúng `pubspec.lock`. Actions mới
được pin commit; token chỉ có quyền đọc source và ghi security results trong job
cần upload SARIF. Không truyền operator secrets, không chạy app/build scripts.
Workflow chạy trên PR, push master, lịch hàng tuần và manual dispatch.

Dependabot alerts, malware alerts và tự tạo security-update PR được bật ngày
22-10-2026. Không auto-merge dependency updates. Gitleaks history gate và GitHub
Secret scanning/push protection vẫn hoạt động; false-positive chỉ đóng sau khi
đối chiếu từng finding, không broad-ignore hoặc tắt scanner.

**Khoảng trống đã biết:** CodeQL không hỗ trợ Dart; OSV dependency scan không
thay thế Dart source audit hoặc Flutter auth/storage/sync regressions. Native
C/C++/Swift/Java và dependencies không có trong `pubspec.lock` chưa được các job
này phân tích. Không có alert không chứng minh app không có lỗ hổng. Evidence
runtime và trạng thái incident xem [task security](tasks/2026-10-22-security-alerts.md).

## Destructive semantics

- Xóa account khi đang đăng nhập: local xóa trước, cloud tombstone retry tới khi
  thành công; thiết bị khác xóa local ở lần sync kế tiếp. Dialog xác nhận phải
  công bố tác động đa thiết bị này trước khi phát event xóa.
- Logout: dừng sync, không xóa local hoặc cloud.
- Xóa Supabase user: cascade xóa record và trigger dọn live Vault secret.
- Breaking migration từ Minimal E2EE drop snapshot/RPC cũ. Không thể decrypt/migrate
  HA1 ciphertext nếu không có recovery key; cần backup/audit trước deploy.

## Threat/failure matrix

| Threat/failure | Hành vi |
|---|---|
| DB dump leak không có Vault root key | Payload Vault vẫn là authenticated ciphertext |
| Backend/root key compromise | TOTP có thể lộ; ngoài zero-knowledge guarantee |
| Cross-user client request | RPC bind `auth.uid()`; direct table bị revoke |
| Network fail | Local giữ nguyên, pending mutation retry |
| Đổi user sau upload fail | Ownership đã bind trước network, không cross-upload |
| Concurrent edit | CAS refresh rồi local pending retry một lần |
| Delete vs stale update | Tombstone thắng, upsert trả `PT410` |
| Metadata corrupt/write fail | Sync dừng trước network hoặc giữ pending; local vẫn dùng |
| Remote payload sai | Không mutate local |
| Logout | Session kết thúc; local/cloud giữ nguyên |
| Realtime mất message/kết nối | Không mất data; resume/reconnect/refresh chạy full sync |
| Cross-user/private-channel join | RLS topic phải khớp `account-sync:<auth.uid()>` |

## Khoảng trống đã biết

- Chưa có independent security audit cho RPC/Vault integration.
- Chưa có background scheduler/push khi OS suspend app, remote wipe hoặc
  ownership-transfer UI.
- Tombstone chưa có retention/compaction policy.
- Browser/local secure storage và physical-device behavior cần runtime evidence.
- Chrome Extension clean-profile/restart/tamper/auth-sync evidence và independent
  security review chưa hoàn tất. Owner có thể waive runtime acceptance chỉ cho
  GitHub Preview khi release note nêu rõ; không được coi đó là stable/store
  release approval.
- External alert, public security contact và off-host restore SLA chưa hoàn tất.

## Release checklist

1. `scripts/agent/check.sh full` pass.
2. Backup + restore rehearsal + Vault root-key custody verified.
3. Migration/health/isolated remote contract pass và test user cleanup verified.
4. Platform artifact/runtime smoke pass; không có secret trong Git/artifact/log.
5. Privacy/support/security contact công khai trước stable/store release.
