# Task: Device-specific wrapped DEK

- Trạng thái: Đang xác minh phát hành; server production và Linux runtime đã pass
- Bắt đầu: 2026-07-19
- Owner: canhvx
- ADR liên quan: `docs/adr/0012-device-specific-hpke-key-wrap.md`

## Mục tiêu

Cho native client còn tin cậy nhận DEK generation mới qua wrap riêng sau rotation,
đồng thời loại một device khỏi current generation mà không buộc mọi device còn lại
nhập recovery key.

## Ngoài phạm vi

- Remote wipe local TOTP hoặc crypto-erase backup lịch sử.
- Web E2EE, post-quantum KEM hoặc active screenshot prevention.
- Tuyên bố security review độc lập khi chưa có reviewer.

## Acceptance criteria

- [x] Protocol dựa trên RFC 9180 thay vì sealed-box tự định nghĩa.
- [x] HPKE Base X25519/HKDF-SHA256/AES-256-GCM khớp official vector.
- [x] Device private key/binding secret có secure-storage fail-closed contract.
- [x] Wrap và membership proof bind exact user/installation/device/generation.
- [x] Context delimiter-collision, envelope oversized/non-canonical và X25519
  low-order key fail closed.
- [x] Migration additive có `key_generation`, device key và wrap table/RPC.
- [x] Enrollment chỉ active sau local wrap + read-back unwrap/proof verification.
- [x] Rotation publish snapshot/recovery wrap/device wrap set atomically.
- [x] Surviving device tự unwrap generation mới; excluded device fail closed.
- [x] Recovery key `HA1` tiếp tục recovery khi device key mất.
- [ ] Remote contract, backup/restore, native two-device runtime và full gate pass.
- [x] Owner chấp nhận ADR trước khi inject/deploy.

## Bằng chứng hiện tại

- Source: `hpke_base_cipher.dart`, `device_key_cipher.dart`, `device_key_store.dart`.
- Official vector pin: CFRG commit
  `5f503c564da00b0687b3de75f1dfbdfc4079ad31`.
- Client coordinator đã được generate DI và được gọi từ setup/recovery/sync/
  recovery-key rotation/vault-key rotation.
- Focused test gồm official vector, tamper/context/key failure,
  delimiter collision, low-order key, canonical envelope, membership proof và
  vault membership verifier/server contract cùng secure-storage record.

## Đánh giá rủi ro

- Lộ credential: private key/binding secret là credential; cấm log, preference,
  fixture thật hoặc server response.
- Mất dữ liệu local: runtime chỉ thay DEK sau read-back decrypt/validate; lost-key
  recovery revoke server key cũ nhưng không xóa local TOTP vault.
- Mất dữ liệu cloud: rotation phải compare-and-swap + atomic device wrap set.
- Migration: additive; current snapshot backfill generation 1.
- Rollback: recovery-key v1 path giữ nguyên; không drop v2 data sớm.
- Tác động platform: native secure storage; Web không enroll.

## Kế hoạch

- [x] Chốt primitive và protocol proposal.
- [x] Thêm model/HPKE/device-key store cùng regression test.
- [x] Review ADR với owner.
- [x] Thiết kế migration/RPC + PostgreSQL contract trước khi apply production.
- [x] Tích hợp repository/use case vào existing SyncBloc flow và ambiguity behavior.
- [x] Rollout production backup-first + restore/remote/Linux runtime.
- [ ] Chạy physical multi-device và CI sau push commit cuối.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Focused analyze | 0 diagnostic | 2026-07-19 |
| HPKE/device-key + sync focused suite | 43 pass | 2026-07-19 |
| PostgreSQL device-wrap/verifier migration contract | Pass | 2026-07-19 |
| `scripts/agent/check.sh full` | 182 Flutter test + mọi gate pass | 2026-07-19 |
| Production backup/off-host/full restore + 53 remote checks | Pass | 2026-07-19 |
| Linux lost-device-key HA1 recovery + rotation runtime | Revision 1→4 pass, cleanup 0 | 2026-07-19 |
| Android AVD + iOS Simulator lost-key runtime | Mỗi target revision 1→4 pass, cleanup 0 | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] ADR

## Bàn giao

ADR đã được owner chấp nhận; client/server, backup/restore, remote regression và
Linux, Android AVD và iOS Simulator lost-key runtime đã pass. Còn physical
two-device, independent review và phát hành binary mới.
