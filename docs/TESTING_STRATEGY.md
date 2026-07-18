# Chiến lược kiểm thử

## Mục tiêu

Ưu tiên chống lộ TOTP credential, mất vault, bypass app lock, cross-tenant access
và cloud overwrite khi conflict. Build pass không thay thế runtime/data contract test.

`scripts/agent/build.sh <target> <env-file>` chạy release-config validator trước
build. Bỏ `<env-file>` chỉ chứng minh compile, không chứng minh bootstrap config.

## Gate canonical

| Scope | Command |
|---|---|
| Docs | `scripts/agent/check.sh docs` |
| Dart/UI | `scripts/agent/check.sh quick` |
| Auth/storage/sync/DI/platform | `scripts/agent/check.sh full` |

`full` phải pass generated-code drift, format (gồm source `integration_test`),
analyze, platform manifest/entitlement contract, Flutter test và encrypted
PostgreSQL migration contract. Nó không tự boot emulator/simulator.

## Coverage hiện tại

98 Flutter tests bao phủ:

- router/auth/logout/offline-local-vault boundary;
- post-login navigation trực tiếp hoặc return an toàn về Settings, stale null auth
  event không ghi đè session hiện tại và auth log redaction;
- repository/BLoC/widget flow revoke session khác: typed failure, confirmation,
  loading chống submit lại và không làm mất authenticated state;
- main-navigation URL/tab mapping và deep-link return qua app-lock bootstrap;
- TOTP URI/validator, countdown nhiều period và lifecycle resume;
- local vault migration, concurrent mutation, corruption rollback, atomic replace
  và generation compaction;
- local-auth startup lock, relock và plugin-error fail closed;
- AES-GCM round-trip, tamper, wrong user, future format và recovery unwrap;
- secure key-store initialize/write/delete verification;
- encrypted setup/cancel/recovery/wrong key/sync/conflict/use-cloud/keep-local;
- recovery-key rotation success/cancel/concurrent conflict và ambiguous verify;
- vault-key rotation success/cancel/conflict, stale-device recovery requirement,
  post-commit transport/verify ambiguity và secure-storage write failure;
- recovery dialog tự quản lý controller, đóng route an toàn khi submit hoặc hủy;
- recovery key bị redact khỏi BLoC event/state transition string;
- remote encrypted mapper, revision response và conflict mapping;
- plaintext bridge release guard.
- public runtime config: HTTPS-only, key role, recovery URL và release plaintext flag.
- Web unavailable tile không hứa đăng nhập/cloud sync khi capability bị tắt.
- Scanner pending permission không còn là màn hình đen; permission denied có
  thông báo, retry và đường quay lại nhập thủ công bằng controller giả không gọi camera.

## Remote contract

Production/staging test dùng isolated user và tự cleanup:

- encrypted RLS/RPC contract: 20 checks, gồm atomic ciphertext/wrapped-key rotation,
  hai session cùng user, revoke session cũ, RLS/RPC chặn JWT cũ ngay và session
  hiện tại tiếp tục hoạt động;
- password recovery token contract: 8 checks;
- Studio network/upstream/Basic Auth contract;
- backup checksum/catalog/tar validation;
- full restore vào database tạm + schema/FORCE RLS probe;
- low-concurrency public Auth health smoke load.

Android Pixel AVD còn xác minh SDK thật gọi bulk revoke: isolated user có hai
session, UI xác nhận action, session count giảm 2→1, current session vẫn ở Settings
và test user/row/app data được cleanup.

Device integration smoke dùng fixture isolated và explicit destructive opt-in đã
pass trên Android Pixel AVD và iOS 26.5 Simulator. Suite kiểm tra bootstrap với
public config, thêm account qua UI, secure-storage round-trip, lifecycle
foreground/hidden, BLoC reload, chuyển Settings/Accounts và local-vault cleanup.
Runner chỉ chấp nhận Android emulator hoặc iOS Simulator; thiết bị thật và macOS
bị từ chối để không chạm vault người dùng.

Remote script cần service-role key nên chỉ chạy trong protected operator context,
không trong untrusted fork CI.

## Build matrix

| Target | Gate |
|---|---|
| Android | Debug build mỗi CI; signed release trước store |
| iOS | Simulator build mỗi CI; signed archive + device/TestFlight trước store |
| macOS | Unsigned compile CI; signed runtime + notarized release trước phân phối |
| Web | Configured release + hardened image contract + CSP browser smoke |
| Windows | Configured native release CI + SHA-256 artifact 14 ngày; installer/device/signing trước phân phối |
| Linux | Isolated release compile + native CI; package/keyring/device smoke trước phân phối |

## Regression rule

- Bug phải có test fail trên behavior cũ nếu có thể tái hiện deterministically.
- Storage/security change phải test success, interruption/corruption và rollback.
- Remote schema change phải có migration test + isolated cross-user contract.
- Field persist phải có round-trip test, không silently default.
- UI conflict/destructive operation cần widget/integration coverage khi ổn định.

## Secret hygiene trong test

- Không dùng secret/JWT/recovery key thật.
- Không snapshot full network request có credential.
- Temp file permission 0700/0600 và cleanup bằng trap.
- Email test dùng domain `.invalid`; user được xóa sau test.
- Không bật shell tracing cho operator harness.
- `scripts/agent/check_secrets.sh` scan toàn bộ Git history và staged diff bằng
  Gitleaks; CI tải binary đã pin sau khi xác minh SHA-256.
- `web-deployment/test.sh` build image từ tar allowlist rồi kiểm tra CSP/cache/SPA,
  read-only, dotfile, no-log và không chứa `.env`.
- `scripts/agent/build_linux_container.sh` archive committed ref vào Ubuntu 24.04
  pin digest, clone đúng Flutter 3.44.6 và xác minh Linux executable.

## Khoảng trống đã biết

1. Device integration mới bao phủ local vault/navigation/lifecycle trên Android
   emulator và iOS Simulator; biometric/camera và secure-storage behavior trên
   thiết bị thật chưa được chứng minh.
2. Chưa có two-device physical E2EE test.
3. Chưa có mailbox SMTP/expired-link E2E.
4. Chưa có long-duration soak hoặc production-scale load test.
5. Windows/Linux installer chưa smoke test trên máy người dùng.
