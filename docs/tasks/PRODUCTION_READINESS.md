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
- [x] 89 test + analyzer + platform/release-config gate pass.
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
| `flutter test` | 89 pass |
| Platform/release config | Pass; Android network + Apple Keychain regression gate |
| Gitleaks full history | Pass; chỉ allowlist exact public RFC test vector |
| `scripts/agent/build.sh host .env` | Android/Web pass; macOS unsigned compile pass |
| iOS 26.5 configured simulator | Pass build + launch; Supabase init thành công |
| Web configured release | Pass + Wasm dry-run |
| Web browser smoke | Pass `/` và direct `/settings` trên production TLS origin; console sạch |
| Web production-serving contract | Pass TLS/proxy/CSP/cache/SPA/read-only/no-log; browser image render sạch |
| Linux release compile | Pass `linux/arm64`, Flutter 3.44.6, Ubuntu 24.04 isolated |
| GitHub Actions run `29633535829` | Pass toàn bộ Web, Android debug, Apple compile, Linux, Windows và quality gates |
| Windows configured artifact | Pass PE x64; 22/22 SHA-256 checksum; không chứa `.env` hoặc signing key |
| Android configured release | Fail closed vì thiếu upload keystore |
| Android Pixel AVD E2E | Pass login return, setup revision 1, recovery-key rotation revision 2, vault-key rotation revision 3 và fresh-device recovery revision 3; cleanup user/row/app data |
| macOS configured release | Bị chặn vì thiếu certificate |
| Remote encrypted contract | 12/12 pass, gồm atomic ciphertext/wrapped-key rotation |
| Remote recovery contract | 8/8 pass |
| Studio proxy contract | Pass |
| Backup restore rehearsal | Full restore DB tạm + schema/FORCE RLS pass |
| Auth smoke load | 100/100 HTTP 200, concurrency 10, p95 ~0,38 giây |

Full `scripts/agent/check.sh full` pass: docs, generated drift, format, analyzer,
platform config, 89 test và encrypted migration contract.

## Rủi ro còn lại

- Signing/store/device/SMTP/alert destination là external gate, không phải source defect.
- Flutter Web còn camera permission/QR scan smoke trên browser-device thật.
- E2EE v1 đã có DEK rotation; individual device/auth-session revoke và Web trust
  model vẫn chưa có.
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
