# Task: Build, deploy và runtime acceptance sau P1/P2

- Trạng thái: Hoàn tất trong các môi trường khả dụng; giới hạn bên dưới
- Bắt đầu / hoàn tất: 2026-10-21
- Owner: Codex; owner cho phép build/deploy và test
- Issue hoặc ADR liên quan: ADR-0024, review P1/P2

## Mục tiêu

Build 1.1.4+18 bằng public production config, deploy Web và kiểm tra runtime;
giữ nguyên vault/profile thật. Không thay schema/backend hoặc publish store.

## Acceptance criteria

- [x] Source snapshot/provenance và artifact SHA256 được giữ.
- [x] Web shadow/public deploy, hash/health/browser smoke pass.
- [x] Windows runtime dùng CompanyName/ProductName namespace riêng.
- [x] Android local vault trên AVD mới; physical upgrade cùng signer không clear data.
- [x] Extension package, clean-profile extension-origin UI/session restart.
- [x] Báo rõ Apple/physical/camera/biometric/Side Panel host còn thiếu.
- [x] Cleanup test user/accounts/Vault secrets có verify.

## Kết quả triển khai

| Target | Artifact/deploy | Runtime thực sự đã chạy |
|---|---|---|
| Web | Production HTTPS 1.1.4+18, image hyper-authenticator-web:1.1.4-p1-20261021r2 | Add/TOTP/reload; login, auto-sync, logout giữ local account; nhận account từ extension |
| Android | Signed APK đúng pin; physical update 1.1.2 (16) lên 1.1.4 (18), model 2211133G | AVD riêng pass local vault CRUD/TOTP/lifecycle; physical install/launch/process sống, không đọc/đổi vault thật |
| Windows | Release x64 portable ZIP unsigned Preview | Namespace riêng pass vault CRUD/TOTP/lifecycle và real Supabase sync |
| Linux | WSL Ubuntu 24.04, release tar.gz/Debian amd64 unsigned Preview | Private XDG/keyring/DBus/Xvfb pass vault và real Supabase sync |
| Extension | MV3 ZIP 1.1.4, local CanvasKit/font/license contract pass | Profile Chromium mới: add/TOTP/reload, login/sync sang Web, restart giữ session, version 18, logout; concurrency/tamper pass |
| iOS/macOS | Chưa build mới | Không có Apple toolchain/device trong phiên |

Web main.dart.js SHA256:
`46a7668a2ae8189a62611a8b24a908dd5e5fe8da59b4bbc2b0458128041ba5c1`.
Shadow/public routes /, /settings, /login, /register, /auth/callback pass;
CSP/no-store hiện diện, /.env bị chặn. Container healthy; backup/restore-drill/
health services loaded, result=success, exit=0. Recovery và Supabase không đổi.

## Nhật ký xác minh

Evidence nằm trong build/deploy-20261021 (ignored).

| Command hoặc test | Kết quả / log | Ngày |
|---|---|---|
| Configured Web release + shadow/live | Pass; web-r2-build.log, web-r2-deploy.log | 2026-10-21 |
| Windows local-vault integration | 1 pass; windows-local-runtime.log | 2026-10-21 |
| Windows real Supabase sync | 1 pass; windows-sync-runtime.log | 2026-10-21 |
| Linux private-keyring vault | 1 pass; linux-local-runtime.log | 2026-10-21 |
| Linux real Supabase sync | 1 pass; linux-sync-runtime.log | 2026-10-21 |
| Android fresh AVD vault | 1 pass; android-local-runtime.log | 2026-10-21 |
| Android final release/apksigner | Pass đúng release pin; android-final-release.log | 2026-10-21 |
| Android physical install -r/launch | Success version 18, process sống; android-physical-upgrade.log | 2026-10-21 |
| Extension final compile/package | Pass; extension-final-compile.log, extension-final-verify.log | 2026-10-21 |
| Real Chrome key race/reopen/concurrency/tamper | Pass; extension-vault-runtime.log | 2026-10-21 |
| Metadata version regression | 1 pass; version-test.log | 2026-10-21 |
| Scoped analyzer/docs/whitespace | Pass; final-scoped-analyze.log, final-docs-gate.log | 2026-10-21 |
| Test user/accounts/linked Vault secrets cleanup | Verified all zero; cleanup.log | 2026-10-21 |
| Final artifact SHA256 + private-input scan | 5/5 pass; artifact-verification.log; local test credential file removed | 2026-10-21 |

Real sync tests cover upload, new-device download, Realtime remote create/delete,
local delete/tombstone và logout. Browser assertions:
WEB_LOGIN_FORM_PASS, WEB_LOGOUT_PRESERVES_LOCAL_VAULT_PASS,
WEB_RECEIVED_EXTENSION_ACCOUNT_PASS, EXT_FINAL_VERSION_SESSION_RESTART_PASS,
EXT_LOGOUT_PASS. Playwright snapshots chuyển vào evidence ignored; không publish
snapshot chứa fixture key/TOTP dù là dữ liệu giả.

## Xử lý lỗi trong rollout

- Bump pubspec/manifest/AppMetadata 1.1.4+18. Image r1 deploy ngắn hạn còn nhãn 17,
  đã thay bằng r2. Metadata regression pass.
- Sync integration chấp nhận upload/delete count 0..1 vì automatic cycle có thể
  chạy trước manual cycle; vẫn bắt buộc durable remote/new-device/tombstone đúng.
- Keystore local ban đầu lệch pin: không bàn giao artifact đó. Đã tìm/verify đúng
  key, sửa local key.properties, giữ config cũ và key đúng ngoài Git trong backup
  operator. APK cuối/physical đều khớp pin:
  `40a53576d95e4abca8ad1a62caa6f12800d313e9fa59c41e256f54cb91754c94`.
- Android stale integration-test plugin registrant hết lỗi sau pub resolution;
  không sửa generated registrant thủ công.
- Git Bash thiếu zip; ZIP cuối tạo bằng Python sau package verifier pass. Lần
  bash trúng WSL/build bị ngắt không tính pass. Final compile trực tiếp, lắp đúng
  bootstrap/local fonts/manifest rồi verify lại.
- Linux sync harness từ chối KEY=value vì yêu cầu JSON. Chuyển sang JSON public,
  chạy private harness pass.
- AVD sau bị dừng khi runtime công cụ khởi động lại: không có final signed-APK
  emulator launch acceptance. AVD vault pass và final physical launch là hai
  bằng chứng riêng.

## Đánh giá rủi ro và giới hạn

- Source working tree nhánh codex/fix-review-p2, base
  `ce4de160300310753e901ea41aa16c6bd65ed48c`, không phải exact-tag CI release.
  Giữ snapshot tracked/untracked và per-file manifest; chưa publish GitHub mới.
- Full gate trước rollout chưa pass do host/tooling/baseline, xem task P1.
  Scoped checks/runtime/build pass không thay thế full CI gate.
- Không downgrade writer về vault v2 sau migration. Compose trước r2 giữ image r1
  hiểu v3; compose trước P1 chỉ để lịch sử. Giữ app identity, không clear data.
- Physical chưa xác minh nội dung vault/migration, camera, import/export,
  biometric/hardware Keystore hoặc nhiều lần suspend/resume. Launch-only không
  chứng minh dữ liệu round-trip.
- Extension dùng UI tại extension origin với service worker thật; native Side
  Panel host, Chrome Store và cross-device dài hạn còn pending.
- Linux build yêu cầu glibc >=2.38; chưa test distro cũ hơn. Windows portable
  chưa kiểm tra NSIS upgrade/code signing/Windows Hello. Chưa có soak/Apple mới.
- Automatic approval review đã từ chối background SSH tunnel/Python HTTP helper
  trong phiên trước; không dùng hai action đó. Public HTTPS/SSH operator cung cấp
  được evidence cần thiết.

## Tác động tài liệu

- [x] PROJECT_STATUS / DEPLOYMENT / TESTING_STRATEGY cập nhật deployment/giới hạn.
- [x] Task P1 giữ evidence cũ, không biến thành full-gate pass.

## Bàn giao

Năm artifact local trong build/deploy-20261021/artifacts: Android signed APK,
Windows portable Preview ZIP, Linux tar.gz/Debian Preview và extension MV3 ZIP.
SHA256SUMS, artifact-manifest.json, README.md mô tả provenance/cách dùng/giới hạn.
Test user/accounts/linked Vault secrets đã xóa; shadow container riêng đã gỡ.
