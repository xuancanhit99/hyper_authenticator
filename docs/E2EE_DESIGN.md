# Thiết kế E2EE snapshot

Trạng thái: **Đã triển khai v1 trên native client và Supabase production**.

## Mục tiêu

Supabase không thấy plaintext TOTP secret. Network/database compromise không đủ
để decrypt vault nếu recovery key và thiết bị không bị compromise. E2EE không bảo
vệ khỏi client đã unlock bị kiểm soát hoàn toàn.

## Key hierarchy

- DEK ngẫu nhiên 256-bit mã hóa account snapshot.
- Recovery key ngẫu nhiên 256-bit, có prefix/version `HA1-`, đóng vai KEK wrap DEK.
- DEK plaintext lưu trong platform secure storage theo Supabase user ID.
- Backend lưu wrapped DEK, không lưu recovery key/DEK plaintext.
- Supabase password không dùng làm KEK/KDF; password reset không phục hồi vault.

## Primitive và encoding

- Package `cryptography` 2.9.0.
- AES-256-GCM, random nonce mỗi encryption.
- Nonce/ciphertext/tag dùng Base64URL.
- AAD bind purpose, format version, Supabase user ID và revision.
- Unknown version hoặc tamper bị từ chối trước local persistence.

## Snapshot

Plaintext canonical chứa đầy đủ `AuthenticatorAccount`, sort theo stable ID.
Remote envelope chứa format, cipher, revision, nonce, ciphertext, auth tag và
wrapped-key envelope. Backend metadata không chứa issuer/account/secret.

## Onboarding đã triển khai

1. Cloud row phải chưa tồn tại.
2. Sinh DEK + recovery key trong memory.
3. Hiển thị recovery key một lần.
4. User xác nhận đã lưu.
5. Encrypt local snapshot revision 1.
6. Atomic publish expected revision 0.
7. Read-after-write verification.
8. Persist DEK + last revision + enabled flag.

Cancel, conflict hoặc network failure trước bước 8 không persist setup state.

## Recovery đã triển khai

1. Download encrypted row.
2. Parse/validate recovery key.
3. Unwrap DEK với user-bound AAD.
4. Authenticate/decrypt snapshot.
5. Validate toàn bộ account.
6. Persist DEK verified.
7. Nếu local khác và không rỗng, chuyển sang explicit conflict.
8. Chỉ atomic replace sau khi user chọn cloud.

Sai key/tamper/future version không mutate local vault.

## Xoay recovery key đã triển khai

Thiết bị đang giữ DEK có thể tạo recovery key 256-bit mới. Client xác thực DEK
với snapshot hiện tại, re-wrap cùng DEK, re-encrypt snapshot bằng nonce mới rồi
atomic publish ở revision kế tiếp. Người dùng phải xác nhận đã lưu key mới trước
khi publish.

- Hủy hoặc revision conflict không đổi remote snapshot; key cũ còn hiệu lực.
- Publish thành công làm key cũ không unwrap được DEK của **snapshot hiện tại**.
- Nếu read-after-write không xác nhận được, UI cảnh báo key mới có thể đã hiệu lực
  và yêu cầu giữ key mới; metadata local không được nâng revision mù.
- Đây không phải DEK rotation/device revocation: thiết bị đã giữ DEK vẫn truy cập.
- Backup lịch sử giữ wrapped DEK cũ nên key cũ có thể mở snapshot backup cũ;
  rotation không xóa hoặc viết lại backup.

## Optimistic revision

Một row/user, monotonic revision. Client encrypt revision `N+1` và RPC chỉ publish
khi current revision bằng `N`. RPC trả `PT409` nếu stale. Client verify response
và re-download trước cập nhật last-seen revision.

Conflict UX:

- **Dùng cloud:** re-check revision rồi atomic replace local.
- **Giữ local:** encrypt local và publish revision mới qua compare-and-swap.

Cloud đổi lần nữa trong lúc review làm operation fail và yêu cầu inspect lại.

## Platform boundary

Android, iOS, macOS, Windows và Linux bật E2EE sync. Web tắt vì browser key storage
khác native trust boundary. Đây là capability gate trong code, không chỉ text UI.

## Migration plaintext

Production hiện không có legacy app data cần migrate. `synced_accounts` vẫn tồn tại
cho rollback/audit; runtime client không inject bridge. Nếu môi trường khác có data:

1. full backup;
2. inventory user/row, không log secret;
3. client/operator đọc + validate plaintext;
4. tạo recovery setup theo user;
5. encrypt và atomic publish;
6. read-after-write decrypt verification;
7. đánh dấu migrated;
8. drop plaintext chỉ trong migration riêng có rollback.

## Bằng chứng

- Crypto/key-store/model tests: tamper, wrong user/key, future format, round-trip.
- Use-case tests: setup/cancel/recovery/conflict/publish conflict/read-after-write.
- Remote contract: 12 checks cho anonymous/RLS/two-user/revision/RPC và atomic
  thay wrapped recovery key.
- Android Pixel AVD E2E: Supabase login, setup vault rỗng revision 1, xoay key qua
  UI và authenticated RLS read xác nhận remote revision 2; test user/row được xóa.
- Release plaintext guard và DI generation test path.

## Khoảng trống đã biết

- Device revocation và DEK rotation.
- Trusted-device/QR transfer.
- Tombstone hoặc history ngoài một current snapshot.
- Browser E2EE threat model.
- Independent security review và physical two-device E2E test.
