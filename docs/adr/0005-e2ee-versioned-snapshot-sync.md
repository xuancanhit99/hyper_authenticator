# ADR-0005: E2EE snapshot với recovery key do người dùng giữ

- Trạng thái: Chấp nhận theo giai đoạn
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế: P-002, P-003
- Bị thay thế một phần bởi: ADR-0012, ADR-0013

## Bối cảnh

Remote row hiện chứa plaintext TOTP secret và upload xóa-rồi-chèn. RLS không bảo vệ
khỏi database/operator compromise và request gián đoạn có thể làm mất snapshot.

## Quyết định

- Client sinh random 256-bit DEK và random 256-bit recovery key.
- AES-256-GCM mã hóa toàn bộ snapshot canonical; AAD bind purpose, format version,
  Supabase user ID và revision.
- Recovery key wrap DEK bằng AES-256-GCM với AAD riêng. Server chỉ lưu ciphertext,
  nonce, tag, wrapped DEK và metadata không nhạy cảm.
- User phải export recovery key entropy cao; password Supabase không derive key.
- Remote dùng một row versioned snapshot cho mỗi user, optimistic revision và atomic
  upsert/RPC. Không xóa snapshot hợp lệ trước khi bản mới commit.
- Client release chỉ bật sync sau onboarding/export/import recovery key và encrypted
  contract test. Plaintext bridge không được bật trong release.
- Thiết bị đang giữ DEK được xoay recovery key bằng KEK mới, re-wrap cùng DEK và
  atomic publish snapshot ở revision kế tiếp. Đây không phải DEK/device rotation.
- Thiết bị đang giữ DEK hợp lệ được chọn xoay cả DEK và recovery key. Client
  re-encrypt current snapshot, atomic publish ciphertext + wrapped DEK mới, rồi chỉ
  persist DEK local sau read-after-write verification.

## Phương án đã cân nhắc

### Key derive từ Supabase password

Không chọn vì đổi/reset password làm phức tạp recovery và ciphertext cho phép offline
guessing. Auth password và vault recovery phải là hai trust boundary độc lập.

### Mã hóa từng record

Cho merge chi tiết hơn nhưng tăng nonce/revision/tombstone surface. Snapshot phù hợp
quy mô authenticator hiện tại và đơn giản hóa atomic publication.

## Hệ quả

- Backend không đọc issuer, account label hoặc TOTP secret.
- Mất mọi trusted device và recovery key đồng nghĩa không thể khôi phục cloud vault.
- Merge hai thiết bị cần revision conflict UI; không được tự động last-write-wins.
- Recovery key cũ không mở current snapshot sau rotation, nhưng vẫn có thể mở
  backup lịch sử chứa wrapped DEK cũ; thiết bị đã giữ DEK không bị revoke.
- DEK rotation làm client tuân thủ chỉ giữ DEK cũ không đọc được current snapshot,
  nhưng không revoke Supabase auth session, không chặn client bị kiểm soát publish
  ciphertext tùy ý và không crypto-erase backup lịch sử.

## Bảo mật và quyền riêng tư

Nonce phải random/unique theo key. Decrypt phải verify tag trước parse/persist. Không
log key/envelope plaintext. Web có threat model riêng và chưa được bật E2EE sync cho
tới khi browser key storage được review.

## Dữ liệu và compatibility

Schema v2 tồn tại song song table plaintext. Client v2 đọc/ghi encrypted snapshot;
plaintext migration cần explicit user action, verified re-read và audit count đã
redact trước khi drop table cũ trong migration riêng.

## Xác minh

Round-trip, tamper từng field, wrong user/key/revision, future version, no-plaintext
fixture, optimistic conflict, recovery/vault-key rotation, cancel/conflict,
post-commit ambiguity, stale-device recovery requirement và interrupted migration
test.

## Rollout

1. Ship crypto/key-store primitives và schema v2 khi sync vẫn khóa.
2. Ship onboarding/recovery-key UI và isolated remote contract.
3. Enable staging E2EE sync; migrate synthetic plaintext.
4. Chỉ sau telemetry/restore rehearsal mới thiết kế drop plaintext table.

## Ghi chú triển khai và thay thế — 22-07-2026

Quyết định cốt lõi của ADR này đã được áp dụng: native client dùng encrypted
versioned snapshot, user-held recovery key, optimistic revision và atomic RPC;
Web vẫn không bật cloud sync. Các câu ở phần bối cảnh, compatibility và rollout
mô tả kế hoạch chuyển tiếp tại ngày chấp nhận, không phải contract hiện tại:

- [ADR-0012](0012-device-specific-hpke-key-wrap.md) bổ sung device-specific HPKE
  wrap, membership proof và key-generation rotation. Session revoke riêng không
  phải cryptographic exclusion; UI xoay vault key thông thường vẫn giữ toàn bộ
  active device có proof hợp lệ.
- [ADR-0013](0013-retire-plaintext-and-require-device-bound-publish.md) kết thúc
  giai đoạn coexistence: plaintext client path bị xóa, bảng legacy chỉ được drop
  fail-closed khi rỗng, và mọi update sau revision đầu tiên phải dùng protocol
  device-bound.

Không khôi phục plaintext bridge để rollback client. Restore backup lịch sử phải
được kiểm tra legacy row, xử lý trong maintenance window rồi áp lại retirement
migration trước khi nhận traffic. Trạng thái production và bằng chứng runtime
hiện tại nằm trong `docs/PROJECT_STATUS.md`.
