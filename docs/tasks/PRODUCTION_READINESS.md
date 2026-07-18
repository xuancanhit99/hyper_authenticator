# Task: Hoàn thiện production readiness

- Trạng thái: Hoàn thành baseline kỹ thuật; còn external release gate
- Bắt đầu/cập nhật: 2026-07-18
- Owner: canhvx
- ADR: 0002, 0003, 0004, 0005, 0007

## Mục tiêu

Đưa project từ alpha local-first tới baseline có encrypted cloud sync, failure
behavior an toàn, backend có backup/restore/health harness và release gate tái hiện.

## Ngoài phạm vi

- Không tự tạo signing certificate, store account, SMTP mailbox hoặc credential
  production thay owner.
- Không tuyên bố device/store test khi chỉ có compile evidence.
- Không drop plaintext compatibility table trong client rollout.

## Acceptance criteria

- [x] Release runtime chỉ dùng encrypted snapshot + atomic revision RPC.
- [x] Onboarding yêu cầu xem/xác nhận recovery key trước khi enable.
- [x] Device mới import key; decrypt failure không overwrite local.
- [x] Conflict/network/retry không delete snapshot hợp lệ.
- [x] Recovery-key rotation atomic; cancel/conflict giữ key cũ và lỗi verify cảnh báo trạng thái mơ hồ.
- [x] DEK + recovery-key rotation atomic; thiết bị giữ DEK cũ cần recovery và
  post-commit ambiguity không nâng metadata mù.
- [x] Không có secret thật trong log/fixture/remote plaintext request.
- [x] 98 test + analyzer + platform/release-config gate pass.
- [x] Bulk revoke mọi session khác; RLS/RPC chặn JWT của session đã revoke ngay
  trong khi session hiện tại và local vault được giữ.
- [x] Local-vault integration smoke pass trên Android emulator và iOS Simulator,
  có explicit reset opt-in và cleanup fixture.
- [x] Linux configured release và local-vault smoke pass trong private D-Bus
  Secret Service/Xvfb sandbox, không chạm keyring hoặc vault người dùng.
- [x] Linux `.deb` candidate sinh dependency bằng `dpkg-shlibdeps`, checksum và
  clean-container install/launch/metadata-upgrade/remove retention smoke.
- [x] Linux authenticated E2EE client runtime pass qua production Supabase với
  isolated user: setup/sync/recovery/recovery-key rotation/vault-key rotation và
  remote cleanup được xác minh, không đưa service-role key vào client hoặc CI.
- [x] Remote E2EE/recovery/Studio contract pass.
- [x] Daily backup, restore rehearsal, encrypted off-host copy và health timer pass.
- [x] Asset/font không rõ license bị loại khỏi release.
- [ ] Signed store artifact/device test — phụ thuộc credential và thiết bị owner.
- [ ] SMTP mailbox/expired link — phụ thuộc mailbox nhận.
- [ ] External alert channel — cần owner chọn destination.

## Thay đổi chính

- Thêm encrypted repository/key/metadata/use case và SyncBloc state machine.
- Thêm atomic local `replaceAccounts`, generation retention và fail-closed app lock tests.
- Gỡ runtime DI của plaintext sync; giữ bridge cho migration test có kiểm soát.
- Đưa settings sync sang onboarding/recovery/conflict UI tiếng Việt.
- Bump version `1.1.0+10`.
- Thay third-party logo pack bằng code-rendered account avatar; bỏ Averta.
- Thêm systemd backup/health, restore rehearsal, `age` off-host pull và LaunchAgent.
- Viết lại canonical docs theo runtime evidence.

## Data/migration/rollback

- Encrypted schema additive; một row/user, `FORCE RLS`, atomic compare-and-swap.
- Không drop `synced_accounts`; production clean không có row legacy cần migrate.
- Disable sync giữ local vault và remote encrypted row.
- Decrypt/validation/conflict failure không mutate local.
- Rollback client không được ghi plaintext; có thể tắt cloud capability và tiếp tục local-only.

## Bằng chứng xác minh

| Command/gate | Kết quả |
|---|---|
| `flutter analyze` | Pass, 0 diagnostic |
| `flutter test` | 98 pass |
| Scanner feedback widget test | 2 pass trên VM và Chrome platform; không gọi camera thật |
| Platform/release config | Pass; Android network + Apple Keychain regression gate |
| Gitleaks full history | Pass; chỉ allowlist exact public RFC test vector |
| `scripts/agent/build.sh host .env` | Android/Web pass; macOS unsigned compile pass |
| iOS 26.5 configured simulator | Pass build + launch; Supabase init thành công |
| Web configured release | Pass + Wasm dry-run |
| Web browser smoke | Pass `/` và direct `/settings` trên production TLS origin; console sạch |
| Web production-serving contract | Pass TLS/proxy/CSP/cache/SPA/read-only/no-log; browser image render sạch |
| Linux configured release + runtime | Pass `linux/x64`; private keyring/Xvfb đi đủ bootstrap, add, storage round-trip, lifecycle, reload, navigation và cleanup |
| Linux Debian artifact | `1.1.0+10` amd64, SHA-256 `b90f880c…f0eaf561`, root entry 0755; dependency/install/launch/metadata-upgrade/remove và package-level data retention pass trong Ubuntu 24.04 sạch |
| Linux authenticated E2EE operator gate | Pass hai lượt trên Ubuntu 24.04 arm64/private Secret Service: setup revision 1, sync revision 2, fresh recovery, recovery-key rotation revision 3 + reject key cũ, vault-key rotation revision 4 + recovery; mỗi lượt xóa isolated user và DB probe cuối trả `test_users=0`, `test_vault_rows=0` |
| GitHub Actions run `29643962397` | Pass 7/7 Web, Android debug, Apple compile, Linux runtime/package, Windows, secret và quality gates tại commit `0128171` |
| Windows configured artifact | Pass PE x64; 22/22 SHA-256 checksum; không chứa `.env` hoặc signing key |
| Android configured release | Fail closed vì thiếu upload keystore |
| Android Pixel AVD E2E | Pass login return, setup revision 1, recovery-key rotation revision 2, vault-key rotation revision 3, fresh-device recovery revision 3 và SDK bulk revoke 2→1 session; cleanup user/row/app data |
| Android Pixel AVD local-vault smoke | Pass UI add, storage round-trip, lifecycle, BLoC reload, navigation và cleanup |
| iOS 26.5 local-vault smoke | Pass cùng contract trên Simulator; cleanup trong `finally` |
| macOS configured release | Bị chặn vì thiếu certificate |
| Remote encrypted contract | 20/20 pass, gồm atomic rotation và active-session revoke enforcement |
| Remote recovery contract | 8/8 pass |
| Studio proxy contract | Pass |
| Backup restore rehearsal | Full restore DB tạm + schema/FORCE RLS/active-session guard pass |
| Auth smoke load | 100/100 HTTP 200, concurrency 10, p95 ~0,38 giây |
| Web production rollout | Image `1.1.0-f88506d` `linux/amd64` healthy; local/container/public SHA-256 khớp; `/`, `/settings`, `/login`, `/reset-password` trả 200; TLS/HSTS/CSP/cache/Permissions-Policy pass |

Full `scripts/agent/check.sh full` pass: docs, generated drift, format, analyzer,
platform config, 98 test và encrypted migration/active-session contract.

## Rủi ro còn lại

- Signing/store/physical-device/SMTP/alert destination là external gate, không phải source defect.
- Flutter Web còn camera permission/QR scan smoke trên browser-device thật.
- Linux còn representative desktop/distro matrix, upgrade từ release lịch sử thật
  và release-channel signing/support metadata. Authenticated E2EE đã pass trên
  debug arm64 container nhưng chưa phải signed amd64 package/public distribution smoke.
- E2EE v1 đã có DEK rotation và bulk revoke session khác; device registry/revoke
  riêng từng thiết bị, device-specific key wrap và Web trust model vẫn chưa có.
- `mobile_scanner` upstream còn Kotlin legacy warning.
- Off-host backup đang phụ thuộc máy Mac thay vì dedicated backup host.

## Tài liệu cập nhật

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEVELOPMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] `DEPLOYMENT.md`
- [x] `E2EE_DESIGN.md`
- [x] ADR asset provenance
