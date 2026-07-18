# ADR-0005: E2EE snapshot với recovery key do người dùng giữ

- Trạng thái: Chấp nhận theo giai đoạn
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế: P-002, P-003
- Bị thay thế bởi:

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
fixture, optimistic conflict, recovery-key rotation/cancel/ambiguous verify và
interrupted migration test.

## Rollout

1. Ship crypto/key-store primitives và schema v2 khi sync vẫn khóa.
2. Ship onboarding/recovery-key UI và isolated remote contract.
3. Enable staging E2EE sync; migrate synthetic plaintext.
4. Chỉ sau telemetry/restore rehearsal mới thiết kế drop plaintext table.
