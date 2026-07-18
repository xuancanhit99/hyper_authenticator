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
- Remote contract: 11 checks cho anonymous/RLS/two-user/revision/RPC.
- Release plaintext guard và DI generation test path.

## Khoảng trống đã biết

- Device revocation và DEK/recovery-key rotation.
- Trusted-device/QR transfer.
- Tombstone hoặc history ngoài một current snapshot.
- Browser E2EE threat model.
- Independent security review và physical two-device E2E test.
