# Thiết kế mã hóa đầu cuối đề xuất

Trạng thái: **Dự kiến**. Không nội dung nào trong tài liệu này chứng minh E2EE đã được triển khai.

Architecture decision record phải chấp nhận thiết kế cuối cùng trước khi implementation.

## Mục tiêu

Supabase và network intermediary không thể đọc TOTP secret hoặc account label trong dữ liệu sync. Client phải phát hiện ciphertext bị sửa và ngăn decryption nhầm giữa user hoặc record.

## Ngoài phạm vi

- Bảo vệ secret khỏi thiết bị client đã unlock và bị compromise hoàn toàn.
- Thay thế Supabase authentication hoặc RLS.
- Tự phát minh cryptographic primitive.
- Khẳng định có thể recovery khi chưa thiết kế key recovery rõ ràng.

## Key hierarchy đề xuất

Dùng hai tầng key:

1. Data Encryption Key (DEK) ngẫu nhiên mã hóa account payload.
2. Key Encryption Key (KEK) wrap DEK cho từng thiết bị hoặc recovery method được cho phép.

Nguồn KEK khả thi:

- key derive từ master password do user cung cấp bằng memory-hard KDF;
- device key được bảo vệ bởi secure hardware hoặc platform secure storage;
- recovery key được export rõ ràng cho user.

Dự án phải quyết định cách thiết bị mới nhận DEK mà backend không nhận key material ở dạng plaintext.

## Payload đề xuất

Versioned envelope có thể có dạng:

~~~json
{
  "formatVersion": 1,
  "recordId": "stable-record-id",
  "cipher": "AES-256-GCM",
  "nonce": "base64",
  "ciphertext": "base64",
  "createdAt": "server-or-client-defined",
  "revision": 1
}
~~~

Plaintext trước encryption chứa đầy đủ field `AuthenticatorAccount` cần để tạo mã. Associated authenticated data phải bind ít nhất:

- format version;
- user identity hoặc tenant scope;
- record ID;
- purpose string;
- revision nếu conflict protocol sử dụng.

Nonce phải duy nhất với cùng một key. Dùng cryptography library để tạo nonce ngẫu nhiên và authenticated ciphertext.

## Key derivation

Nếu chọn master password:

- lưu random salt riêng cho mỗi user;
- dùng memory-hard KDF đã review và chạy được trên mọi target;
- định nghĩa parameter trong versioned envelope hoặc key metadata;
- rate limit chỉ là defense in depth vì encrypted blob cho phép offline guessing;
- không ngầm tái sử dụng mật khẩu đăng nhập Supabase;
- không log password, derived key, salt, DEK hoặc recovery data.

Nếu Dart stack được chọn không có KDF cross-platform phù hợp, phải xử lý dependency đó trước khi chấp nhận thiết kế.

## Onboarding thiết bị

Thiết kế cuối phải định nghĩa một hoặc nhiều cách:

- quét QR truyền dữ liệu mã hóa device-to-device;
- nhập recovery key entropy cao;
- nhập master password để derive KEK;
- phê duyệt thiết bị mới từ thiết bị tin cậy đang có.

Chỉ xác thực Supabase không được làm lộ DEK.

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

## Quyết định mở

- Cipher suite và library.
- KDF và parameter.
- Encryption theo record hay snapshot.
- Key rotation và device revocation.
- Recovery model.
- Conflict protocol và field associated data.
- Metadata privacy.
- Kỳ vọng secure deletion theo platform.
- Web support và browser threat model.
