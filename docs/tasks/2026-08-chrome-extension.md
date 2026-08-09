# Task: Chrome Extension Side Panel foundation

- Trạng thái: Source/package và current-profile smoke đã có; GitHub Preview ZIP
  theo owner waiver, chưa có clean-profile/tamper/cross-device Side Panel evidence
- Bắt đầu: 2026-08-09
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0022

## Mục tiêu

Tạo Chrome Extension MV3 để dùng TOTP trực tiếp qua Side Panel mà không mở rộng
browser-page permission hoặc làm yếu local vault/security boundary.

## Ngoài phạm vi

- Không autofill, content script, đọc tab/browser history/cookie hoặc scanner
  camera trong MVP.
- Không migrate hosted Web storage hoặc thay đổi Supabase schema/RPC.
- Không publish Chrome Web Store cho tới khi evidence runtime và legal metadata
  hoàn tất.

## Acceptance criteria

- [x] MV3 Side Panel shell, action worker, CSP/permission/host allowlist.
- [x] Flutter entrypoint/router không retain mobile scanner/CDN decoder.
- [x] Local CanvasKit/WASM và static verifier reject remote executable/PWA worker.
- [x] Extension local vault/sync metadata dùng encrypted IndexedDB WebCrypto;
  Supabase session + PKCE không fallback localStorage.
- [x] Current profile: Side Panel render, login Supabase, sync và session còn
  sau đóng/mở Chrome (manual owner smoke).
- [x] Local vault v2/sync format native không đổi; native fixture/test pass.
- [ ] Clean Chrome profile load unpacked, side panel render, restart/persist/tamper smoke.
- [ ] Auth + cross-device account sync/realtime acceptance trên Chrome.
- [ ] QR import chỉ sau khi local-bundle decoder + tests/permission review pass.
- [x] GitHub Preview asset/provenance: ZIP versioned + checksum/static verifier;
  runtime acceptance được owner waive và phải disclosure trong release note.
- [ ] Chrome Store trusted-test rollout.

## Bằng chứng hiện tại

- Source: `lib/main_extension.dart`, `lib/chrome_extension`, `chrome_extension/`.
- Build: `scripts/agent/build_chrome_extension.sh` tạo ZIP versioned + SHA-256 và
  unpacked; GitHub Preview publisher chỉ lấy ZIP từ exact successful tag CI;
  verifier bắt buộc Roboto tiếng Việt nằm trong FontManifest để CanvasKit không
  gọi Google Fonts vốn bị CSP chặn. Đây chưa phải runtime evidence.
- Giả định: Chrome 114+ hỗ trợ Side Panel và structured-clone `CryptoKey` trong
  extension IndexedDB. Cần xác minh trên clean profile trước release.

## Đánh giá rủi ro

- Lộ credential: profile/extension-origin compromise vẫn có thể đọc plaintext
  trong runtime; CSP/local code và non-extractable IndexedDB key chỉ giảm bề mặt.
- Mất dữ liệu local: xóa extension/profile/IndexedDB key làm mất local-only
  extension vault; account đã cloud-sync có thể tải lại sau login.
- Mất dữ liệu cloud: không có migration/cloud write path mới; ADR-0020 giữ nguyên.
- Migration: không đổi local v2 hoặc remote schema; chỉ thêm storage adapter.
- Rollback: bỏ extension không xóa vault trên native/Web hay cloud.
- Tác động platform: native/Web và existing release artifact phải giữ behavior.

## Kế hoạch

- [x] Tách route contract và default-router registration khỏi extension entrypoint.
- [x] Tạo encrypted storage abstraction/session adapter và package harness.
- [ ] Load/test extension trong Chrome profile riêng, không dùng real TOTP secret.
- [x] Thêm CI artifact contract và GitHub Preview asset/version/checksum verifier.
- [ ] Thêm runtime E2E clean-profile/tamper/cross-device evidence.
- [ ] Duyệt local-bundled QR import phase riêng.
- [ ] Chuẩn bị store privacy/support/security contact, images và disclosure.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `flutter analyze` | Pass, 0 issue | 2026-08-09 |
| selected Dart regression tests | Pass sau refactor storage/router | 2026-08-09 |
| `scripts/agent/build_chrome_extension.sh` | Pass, local-only package verifier | 2026-08-09 |
| `scripts/agent/check.sh full` | Pass: docs/codegen/format/analyze, 206 Flutter test, migration/release/infra harness; ZIP version/checksum/public verifier contract | 2026-08-09 |
| `scripts/supabase/test_remote_account_sync_contract.sh` | Pass 26/26 với hai isolated user; Realtime + cleanup verified | 2026-08-09 |
| `scripts/agent/mobile_account_sync_operator.sh` trên iPhone 16 Pro Simulator | Auth session/local-vault + upload/download/Realtime/tombstone pass; isolated user cleanup verified | 2026-08-09 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [ ] `SUPABASE_INTEGRATION.md` — không đổi server contract
- [x] `DEVELOPMENT.md`
- [x] `DEPLOYMENT.md`
- [x] ADR-0022

## Bàn giao

Không được gọi foundation này là Chrome Web Store hoặc production-ready release.
Bàn giao phải ghi rõ build/package evidence, runtime profile evidence,
clean-profile/tamper/cross-device gaps, limitation không QR/protected export và
tình trạng public privacy/support URL.
