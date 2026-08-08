# ADR-0022: Chrome Extension dùng MV3 Side Panel và encrypted IndexedDB vault

- Trạng thái: Chấp nhận cho implementation foundation; chưa được phép public release
- Ngày: 2026-08-09
- Owner: HyperZ
- Bổ sung: ADR-0002, ADR-0010, ADR-0020, ADR-0021
- Bị thay thế bởi:

## Bối cảnh

Hyper Authenticator đã có Web app nhưng một website không thể được đóng gói
nguyên trạng thành Chrome Extension. Manifest V3 cấm remotely hosted executable
code; Web build cũ kéo ZXing WASM từ CDN thông qua `mobile_scanner`. Web cũng
dùng browser-storage trust boundary, trong khi `flutter_secure_storage_web` mặc
định có thể giữ wrapping/encryption material cạnh ciphertext trong localStorage.

Chrome Extension phải vẫn local-first khi không đăng nhập, nhưng local vault
của extension không tự chia sẻ với origin Web hoặc Keychain/Keystore native.
Đăng nhập account-managed sync là con đường đồng bộ dữ liệu giữa các surface.

## Quyết định

### Surface và permission MVP

- Dùng Manifest V3, Chrome 114+, toolbar action mở Side Panel.
- Không dùng content script, `tabs`, `activeTab`, `scripting`, `cookies`,
  `<all_urls>`, `idle`, `alarms` hoặc `chrome.storage.sync` trong MVP.
- Permission chỉ gồm `sidePanel`; host permission chỉ gồm HTTPS origin Supabase
  production chính xác. CSP chỉ cho self-hosted script/WASM và `connect-src`
  tới Supabase/WSS origin đó.
- Service worker không giữ TOTP, session hay timer. Side Panel hiển thị mới sở
  hữu countdown và foreground sync.

### Bundle và UI

- Dùng entrypoint/router `lib/main_extension.dart` độc lập để tái sử dụng
  domain, BLoC, TOTP, auth và sync mà không import mobile QR scanner.
- MVP gồm list/search/copy/countdown, manual add/edit/delete, Settings và
  email/password account sync. Protected QR export và QR scanner/import bị
  loại khỏi extension route/UI.
- Flutter engine/WASM và Roboto hỗ trợ tiếng Việt nằm trong ZIP. CSP không cho
  phép Google Fonts hay executable code từ xa. Build harness fail nếu thiếu font
  local hoặc còn remote JS/WASM, ZXing CDN, remote `<script>`, `importScripts`
  hay PWA service worker.

### Local vault và auth session

- `SecureKeyValueStore` là abstraction cho vault v2/sync metadata. Native giữ
  `FlutterSecureStorage`; Chrome Extension dùng bridge local `vault.js`.
- Bridge dùng IndexedDB với object store `keys`/`records`; tạo AES-256-GCM
  `CryptoKey` `extractable=false`, persist bằng structured clone và không export
  raw key bytes. Mỗi record dùng nonce 96-bit mới, authenticated additional data
  gắn namespace/key và GCM tag 128-bit.
- Supabase session và GoTrue PKCE verifier dùng cùng encrypted store, namespace
  riêng. Không được fallback sang `localStorage` hoặc `chrome.storage`.
- Local-vault v2/sync metadata format không đổi. Xóa extension/profile hoặc mất
  IndexedDB key mất local-only data của extension; account đã sync vẫn tải lại
  sau login từ server-managed cloud.

## Phương án đã cân nhắc

### Đóng gói trực tiếp Flutter Web hiện có

Không chọn vì Web bundle cũ có remote ZXing executable và website router kéo QR
camera vào artifact. Cả hai vi phạm hoặc làm khó review MV3.

### `flutter_secure_storage_web` mặc định

Không chọn cho extension vì key material không tạo boundary đủ rõ với
localStorage ciphertext. Nó vẫn giữ cho hosted Web hiện tại; thay đổi đó là một
quyết định/migration Web riêng.

### `chrome.storage.local`/`sync` cho TOTP

Không chọn. `sync` có quota nhỏ và không dành cho credential; `local` không là
vault encryption boundary. Extension chỉ dùng IndexedDB/WebCrypto cho record
nhạy cảm.

### Extension autofill ngay trong MVP

Không chọn. Autofill cần page access/content script/host permission rộng hơn,
tăng disclosure và Chrome Web Store review surface. Cần ADR riêng.

## Hệ quả

### Tích cực

- Side Panel đủ không gian cho TOTP, giữ khi chuyển tab và không cần đọc web
  page của người dùng.
- ZIP có contract kiểm tra local executable code trước release.
- Native/local vault behavior không đổi; login sync vẫn dùng cùng RPC/CAS/
  tombstone/Realtime protocol.

### Tiêu cực và giới hạn

- Extension UI không có camera/QR import/export trong MVP.
- Browser profile, extension code đã cài, XSS trong extension origin và malware
  trên máy vẫn là trust boundary. Non-extractable key không biến browser thành
  Keychain/Keystore và không phải E2EE.
- Không có app lock/fresh OS auth tương đương native; protected export bị ẩn.
- Side Panel đóng/suspend không hứa realtime/background sync. Reopen/resume,
  auth restore và mutation vẫn gọi full sync.
- Chrome Web Store release bị chặn cho đến khi runtime smoke trên clean profile,
  privacy/support URL, listing assets, disclosure và review hoàn tất.

## Failure behavior và rollback

- Bridge/vault fail hoặc ciphertext không decrypt: local data source trả typed
  storage failure, không reset/rò plaintext. Vault v2 reader còn generation
  hợp lệ thì rollback theo contract ADR-0002.
- Session/PKCE storage fail: auth failure, không fallback plaintext.
- Rollback client: gỡ extension hoặc quay lại build trước chỉ tác động local
  extension storage; không thay remote schema/RPC và không xóa native/Web vault.
- Chỉ owner có thể xóa profile/extension data; không đưa destructive clear vào
  service worker hoặc release harness.

## Xác minh cần có

- Dart test secure session/PKCE namespace và local-vault regression.
- Package verifier: MV3/CSP/permission/host allowlist/local CanvasKit, không
  remote executable, scanner CDN hoặc PWA worker.
- Clean Chrome profile: load unpacked, restart, local vault round-trip,
  browser restart, extension disable/re-enable, login/session restore, sync và
  tampered ciphertext fail closed.
- Trước public store: independent security review và Chrome Web Store policy/
  privacy review.
