# Task: Device-specific wrapped DEK

- Trạng thái: Đang thiết kế; primitive staged, chưa inject/deploy
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
- [ ] Migration additive có `key_generation`, device key và wrap table/RPC.
- [ ] Enrollment chỉ active sau local wrap + read-back unwrap verification.
- [ ] Rotation publish snapshot/recovery wrap/device wrap set atomically.
- [ ] Surviving device tự unwrap generation mới; excluded device fail closed.
- [ ] Recovery key `HA1` tiếp tục recovery khi device key mất.
- [ ] Remote contract, backup/restore, native two-device runtime và full gate pass.
- [ ] Owner chấp nhận ADR trước khi inject/deploy.

## Bằng chứng hiện tại

- Source: `hpke_base_cipher.dart`, `device_key_cipher.dart`, `device_key_store.dart`.
- Official vector pin: CFRG commit
  `5f503c564da00b0687b3de75f1dfbdfc4079ad31`.
- Primitive không có annotation DI và chưa được gọi từ runtime.
- Focused test: 17 test pass gồm hai official vector, tamper/context/key failure,
  delimiter collision, low-order key, canonical envelope, membership proof và
  secure-storage record.

## Đánh giá rủi ro

- Lộ credential: private key/binding secret là credential; cấm log, preference,
  fixture thật hoặc server response.
- Mất dữ liệu local: staged primitive chưa mutate vault; runtime sau này chỉ thay
  DEK sau read-back decrypt/validate.
- Mất dữ liệu cloud: rotation phải compare-and-swap + atomic device wrap set.
- Migration: additive; current snapshot backfill generation 1.
- Rollback: recovery-key v1 path giữ nguyên; không drop v2 data sớm.
- Tác động platform: native secure storage; Web không enroll.

## Kế hoạch

- [x] Chốt primitive và protocol proposal.
- [x] Thêm model/HPKE/device-key store cùng regression test.
- [ ] Review ADR với owner.
- [ ] Thiết kế migration/RPC + PostgreSQL contract trước khi apply production.
- [ ] Tích hợp repository/use case/BLoC/UI và ambiguity behavior.
- [ ] Chạy runtime multi-device, rollout backup-first và CI.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Focused analyze | 0 diagnostic | 2026-07-19 |
| HPKE/device-key focused suite | 13 pass | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [ ] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [ ] `SUPABASE_INTEGRATION.md`
- [ ] `DEPLOYMENT.md`
- [x] ADR

## Bàn giao

Primitive và persisted local key format mới chỉ staged, không thay runtime/data
contract production. Cần owner chấp nhận ADR trước schema/client integration.
