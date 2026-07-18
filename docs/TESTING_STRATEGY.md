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

`full` phải pass generated-code drift, format, analyze, platform manifest/
entitlement contract, Flutter test và encrypted PostgreSQL migration contract.

## Coverage hiện tại

71 Flutter tests bao phủ:

- router/auth/logout/offline-local-vault boundary;
- main-navigation URL/tab mapping và deep-link return qua app-lock bootstrap;
- TOTP URI/validator, countdown nhiều period và lifecycle resume;
- local vault migration, concurrent mutation, corruption rollback, atomic replace
  và generation compaction;
- local-auth startup lock, relock và plugin-error fail closed;
- AES-GCM round-trip, tamper, wrong user, future format và recovery unwrap;
- secure key-store initialize/write/delete verification;
- encrypted setup/cancel/recovery/wrong key/sync/conflict/use-cloud/keep-local;
- remote encrypted mapper, revision response và conflict mapping;
- plaintext bridge release guard.
- public runtime config: HTTPS-only, key role, recovery URL và release plaintext flag.
- Web unavailable tile không hứa đăng nhập/cloud sync khi capability bị tắt.

## Remote contract

Production/staging test dùng isolated user và tự cleanup:

- encrypted RLS/RPC contract: 11 checks;
- password recovery token contract: 8 checks;
- Studio network/upstream/Basic Auth contract;
- backup checksum/catalog/tar validation;
- full restore vào database tạm + schema/FORCE RLS probe;
- low-concurrency public Auth health smoke load.

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

1. Chưa có device integration suite cho Keychain/Keystore/biometric/camera.
2. Chưa có two-device physical E2EE test.
3. Chưa có mailbox SMTP/expired-link E2E.
4. Chưa có long-duration soak hoặc production-scale load test.
5. Windows/Linux installer chưa smoke test trên máy người dùng.
