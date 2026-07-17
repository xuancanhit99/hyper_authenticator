# Thiết kế mã hóa đầu cuối

Trạng thái: **Chấp nhận theo giai đoạn** trong
[ADR-0005](adr/0005-e2ee-versioned-snapshot-sync.md).

**Đã triển khai:** AES-256-GCM snapshot primitive, AAD bind user/revision, random
DEK, user-held recovery key wrapping, secure key-store primitive, schema/RPC v2 và
regression/migration test.

**Khoảng trống đã biết:** onboarding/export/import recovery key UI, client remote
orchestration, staging deployment, conflict UX và plaintext migration chưa hoàn tất;
do đó release cloud sync vẫn bị khóa và chưa được mô tả là E2EE production.

## Mục tiêu

Supabase và network intermediary không thể đọc TOTP secret hoặc account label trong dữ liệu sync. Client phải phát hiện ciphertext bị sửa và ngăn decryption nhầm giữa user hoặc record.

## Ngoài phạm vi

- Bảo vệ secret khỏi thiết bị client đã unlock và bị compromise hoàn toàn.
- Thay thế Supabase authentication hoặc RLS.
- Tự phát minh cryptographic primitive.
- Khẳng định có thể recovery khi chưa thiết kế key recovery rõ ràng.

## Key hierarchy đã chọn

Dùng hai tầng key:

1. Data Encryption Key (DEK) ngẫu nhiên mã hóa account payload.
2. Key Encryption Key (KEK) wrap DEK cho từng thiết bị hoặc recovery method được cho phép.

Recovery key ngẫu nhiên 256-bit có prefix/version `HA1-` là KEK để wrap DEK.
Thiết bị giữ DEK trong platform secure storage theo Supabase user ID. Thiết bị mới
nhập recovery key, tải wrapped DEK rồi unwrap local; backend không nhận key plaintext.
Supabase password không được dùng làm KEK/KDF.

## Payload đã chọn

Versioned envelope có thể có dạng:

~~~json
{
  "formatVersion": 1,
  "cipher": "AES-256-GCM",
  "nonce": "base64",
  "ciphertext": "base64",
  "createdAt": "server-or-client-defined",
  "revision": 1
}
~~~

Plaintext là snapshot canonical chứa đầy đủ `AuthenticatorAccount`, sort theo stable
ID. Associated authenticated data bind:

- format version;
- user identity hoặc tenant scope;
- purpose string;
- revision.

Nonce phải duy nhất với cùng một key. Dùng cryptography library để tạo nonce ngẫu nhiên và authenticated ciphertext.

## Primitive và encoding

Client dùng package `cryptography` 2.9.0 và AES-256-GCM. Nonce được library sinh
random cho mỗi encrypt. Nonce, ciphertext và tag dùng Base64URL. Không tự triển khai
cipher/KDF và không dùng password-derived key trong format v1.

## Onboarding thiết bị

Version đầu dùng nhập recovery key entropy cao. UI phải hiển thị key một lần và yêu
cầu user xác nhận đã lưu trước enable sync. QR/trusted-device transfer là mở rộng sau.

## Recovery

Recovery là quyết định sản phẩm và bảo mật, không phải chi tiết implementation.

Các lựa chọn:

- **Không recovery:** mất key đồng nghĩa mất dữ liệu sync.
- **Recovery key do user giữ:** entropy cao, chỉ hiển thị một lần, backend không lưu plaintext.
- **Threshold hoặc trusted-device recovery:** phức tạp hơn và cần threat review riêng.

Không khẳng định email reset mật khẩu có thể khôi phục dữ liệu E2EE trừ khi cryptographic design cho phép rõ ràng.

## Tích hợp synchronization

Upload:

1. Validate và serialize account.
2. Lấy DEK vào memory.
3. Tạo nonce duy nhất.
4. Encrypt với authenticated associated data.
5. Chỉ upload versioned envelope và concurrency metadata không nhạy cảm.

Download:

1. Validate shape và version được hỗ trợ của envelope.
2. Lấy DEK.
3. Verify rồi decrypt bằng associated data.
4. Validate plaintext model.
5. Chỉ persist local sau khi authentication và validation thành công.

Decryption hoặc validation failure không được ghi đè record local hợp lệ.

## Migration plaintext

Trước khi bật E2EE ở production:

1. Kiểm kê row plaintext cũ.
2. Release client có thể đọc format cũ lẫn encrypted nhưng chỉ ghi encrypted.
3. Xác thực user và thiết lập DEK.
4. Download, validate, encrypt và migrate snapshot atomically.
5. Xác minh đọc encrypted thành công.
6. Xóa field plaintext.
7. Theo dõi migration completion mà không lộ secret.
8. Định nghĩa rollback trước khi xóa dữ liệu cũ.

## Yêu cầu kiểm thử

- Known-answer test cho encryption và decryption.
- Chiến lược test tính duy nhất của random nonce.
- Test nonce, ciphertext, tag, associated data, record ID và version bị sửa.
- Test sai user, sai device key và sai master password.
- Hành vi với format version cũ và tương lai.
- Migration bị gián đoạn và retry.
- Onboarding và revoke đa thiết bị.
- Recovery thành công và thất bại.
- Không có plaintext secret trong remote request fixture, log, crash report hoặc database row.
- Ghi lại performance trên target platform và giới hạn secure memory.

## Quyết định triển khai còn mở

- Key rotation và device revocation.
- Conflict UX khi optimistic revision mismatch.
- Metadata/timing privacy.
- Kỳ vọng secure deletion theo platform.
- Web support và browser threat model.
