# Chiến lược kiểm thử

Test ưu tiên data integrity, credential boundary và hành vi người dùng có thể
quan sát. Test pass chỉ là bằng chứng cho source/target đã chạy, không thay thế
physical-device hoặc production evidence.

## Gate

| Scope thay đổi | Command tối thiểu |
|---|---|
| Tài liệu | `scripts/agent/check.sh docs` |
| Dart/UI | `scripts/agent/check.sh quick` |
| Auth/storage/sync/routing/DI/plugin/platform | `scripts/agent/check.sh full` |
| Schema Supabase | `scripts/agent/check.sh backend` + remote contract sau deploy |
| Platform-specific | Build và runtime smoke target đó |

`full = app + backend + release + infra`.

## Unit/domain

- TOTP: Base32, algorithm, digits, period, bounded URI và duplicate parameter.
- Standard/Google import: parse, batch assembly, preview, exact dedupe, cancel và
  validate-all before commit.
- Export: unsupported semantics, multi-part split, timeout/lifecycle cleanup và
  secret redaction.
- Local vault: legacy migration, copy-on-write generation, corrupt latest
  fallback, write/delete/import/replace atomicity và compaction.
- Account sync: first-login ownership, merge upload/download, dirty-vs-clean,
  cross-user isolation, offline failure, CAS retry và deletion tombstone.
- Realtime wake-up: auth subscribe/switch/logout, reconnect, debounce, error
  fallback, own-topic authorization, client-send denial và payload allowlist.
- Theme: six style/brightness combinations, transition opacity, persistence race,
  cache repair và 320 px/200% accessibility.
- Chrome Extension: Supabase session/PKCE namespace đi qua secure-store; native
  local-vault regression vẫn pass sau storage abstraction. Package gate kiểm tra
  MV3 Side Panel/CSP/permission/host allowlist, local CanvasKit/WASM/Roboto,
  không CDN executable/PWA worker và vault WebCrypto contract.

## Widget/navigation

- Add/Edit/Delete/search/countdown/account actions.
- App Lock success/cancel/error và lifecycle relock.
- Privacy Shield opaque/interaction/semantics behavior.
- Stateful shell tab state, reselect-to-root và resume responsiveness.
- Settings cloud states: local-only, automatic sync progress/success/failure và
  retry; source/widget không được tái xuất hiện recovery/setup controls.
- Cloud auth entry: khách mở Login với `returnTo=/settings`; đăng xuất cần xác
  nhận và integration smoke phải chứng minh local vault còn nguyên.
- Accessibility: text contrast, 48 px tap target, keyboard focus, text scale 200%
  và narrow viewport.

## Integration/runtime

`integration_test/account_sync_smoke_test.dart` cần isolated user và explicit
mutation opt-in. Luồng tối thiểu:

1. sign in;
2. tạo local account và auto upload;
3. fresh in-memory device tải account chỉ từ session;
4. xóa local và publish tombstone;
5. remote-only mutation tự download/xóa local qua private Realtime signal;
6. verify tombstone/signal không chứa payload.

Harness operator phải tạo/xóa isolated user ngoài client và xác minh cleanup.
Không truyền service-role key vào Flutter process.

`integration_test/local_vault_smoke_test.dart` chạy trên private Linux keyring và
Windows Credential Manager runner. Acceptance của bước render phải đợi nội dung
mã TOTP hợp lệ, không chỉ đợi widget xuất hiện vì `FutureBuilder` có thể vẫn đang
hiển thị placeholder. Scroll trong live app dùng jump + bounded pump; không dùng
`pumpAndSettle()` khi countdown tiếp tục tạo frame.

## PostgreSQL contract

```bash
scripts/supabase/test_account_sync_migration.sh
```

Local harness phải kiểm tra Vault ciphertext, object cũ absent, table/RPC/trigger,
ACL, RLS/FORCE RLS, tenant isolation, payload bounds, CAS `PT409` và tombstone
`PT410`; Realtime contract kiểm tra private topic, signal allowlist, client-send
denial, authorization probe có nullable `private` và không bật Postgres Changes
trên account table.

Sau production deploy chạy
`scripts/supabase/test_remote_account_sync_contract.sh` với hai isolated users.
Remote pass chỉ hợp lệ khi test row/user được cleanup và xác minh absent.

## Release/infra

- GitHub Preview asset/checksum/signature/public-download contract, gồm Chrome
  Extension ZIP/version/checksum/static package verifier khi asset đó có mặt.
- Web runtime + rollback contract.
- Nginx Proxy Manager secrets/backup/deploy/route/rollback contract.
- Supabase backup checksum/catalog/full restore rehearsal và health check.
- Linux account-sync working-tree archive lọc path tracked đã xóa nhưng vẫn giữ source
  tracked/untracked non-ignored và symlink bằng danh sách NUL-delimited.

Static shell syntax test không chứng minh production đã deploy hoặc restore được;
runbook phải lưu runtime evidence riêng.

## Platform matrix

| Target | Build | Runtime cần chứng minh |
|---|---|---|
| Android | signed release APK | install/upgrade, camera, biometric, secure storage, account sync |
| iOS | development/Ad Hoc/archive | install/launch, camera, Face ID, Keychain, account sync |
| macOS | release app | Keychain, local auth, scanner, packaging/notarization |
| Windows | release/NSIS | Credential Manager, Windows Hello, installer upgrade |
| Linux | release/deb | Secret Service/keyring, desktop lifecycle, account sync |
| Web | release/Nginx | local TOTP, camera, reset-password và account sync |
| Chrome Extension | MV3 ZIP/unpacked | clean profile, Side Panel, IndexedDB vault restart/tamper, session restore và foreground sync |

Simulator/emulator bổ sung nhưng không thay physical camera/biometric evidence.

## Regression rule

- Bug phải có test fail trên hành vi cũ nếu có thể tái hiện tự động.
- Storage/security change phải test success, failure, rollback/no-mutation.
- Persisted field phải có round-trip test.
- UI sensitive flow phải có lifecycle/cancel/timeout test.
- Không đưa real secret, full URI, password, email production hoặc token vào
  fixture/snapshot output.

## Baseline hiện tại

`PROJECT_STATUS.md` là nguồn duy nhất ghi số test/gate gần nhất. Không copy con số
lịch sử sang file này vì dễ biến thành claim stale.
