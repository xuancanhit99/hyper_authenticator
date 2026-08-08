# ADR-0018: Biên backup file mã hóa bằng password

> **Bị thay thế bởi ADR-0019.** Portable backup file không còn trong product,
> source hoặc platform integration; nội dung dưới đây chỉ là lịch sử quyết định.

- Trạng thái: Chấp nhận
- Ngày: 2026-07-27
- Cập nhật runtime boundary: 2026-07-29
- Owner: HyperZ
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

QR `otpauth` và Google migration phục vụ chuyển account giữa authenticator nhưng
không phải backup đầy đủ: batch có giới hạn, custom TOTP semantics có thể không
round-trip và QR là credential disclosure trực tiếp. Backup cloud hiện tại phụ
thuộc Supabase identity, recovery key và device-bound envelope nên không phải file
portable do người dùng tự giữ.

Ứng dụng cần một file chứa snapshot đầy đủ, mở được offline trên thiết bị khác
bằng password. Đây đồng thời là boundary cryptography, persisted format và thao
tác phá hủy local data nên phải version, fail closed và có atomic restore.

## Quyết định

1. File có media extension `.hyauth`, canonical compact JSON và top-level
   `format = hyper-authenticator-encrypted-backup`, `format_version = 1`.
   Envelope v1 chỉ nhận exact key set và giới hạn 8 MiB.
2. KDF là Argon2id v19, output 32 byte, salt ngẫu nhiên 16 byte. Encoder v1 dùng
   OWASP minimum 19 MiB, 2 iteration, parallelism 1. Decoder persist và kiểm tra
   parameter trong bounded allowlist trước khi cấp phát KDF để hỗ trợ nâng cost
   sau này mà không nhận resource-exhaustion metadata tùy ý.
3. Payload được mã hóa bằng AES-256-GCM với nonce ngẫu nhiên 12 byte và tag 16
   byte. Canonical AAD bind purpose, file version, toàn bộ KDF metadata/salt,
   cipher name và nonce; thay header hoặc ciphertext đều làm xác thực thất bại.
4. Plaintext có `payload_format_version = 1`, UTC `created_at` và danh sách
   account theo đúng local order. Decoder exact-validate schema, type, giới hạn,
   unique stable ID và toàn bộ TOTP semantics trước khi trả snapshot.
5. Sai password và tamper trả cùng một lỗi không tiết lộ oracle. Future
   version/algorithm, non-canonical JSON/base64, oversized field/file và KDF ngoài
   bound bị từ chối trước mutation.
6. BLoC chỉ giữ encrypted bytes hoặc decrypted candidate trong private memory.
   State preview chỉ có metadata cần người dùng nhận diện; event chứa password và
   mọi object nhạy cảm override `toString` để redact. Candidate bị bỏ khi cancel,
   app rời foreground, timeout, restore thành công hoặc BLoC đóng.
7. Restore luôn preview, hiển thị số account local sẽ bị thay và yêu cầu user gõ
   cụm xác nhận. Chỉ sau đó repository mới gọi `replaceAccounts()` một lần; local
   COW generation bảo đảm failure trước commit marker giữ snapshot active cũ.
8. File picker chỉ chạy sau explicit user gesture. Cancel open/save/password/
   preview là no-op. File không được tự upload, ghi clipboard, lưu trong
   preference, route hoặc Supabase.
9. Dùng Flutter-maintained `file_selector` cho open cùng Web/desktop save. iOS
   dùng `share_plus` để user chọn Files/provider qua system share sheet. Android
   dùng MethodChannel hẹp tới Storage Access Framework
   `ACTION_CREATE_DOCUMENT`; chỉ trả success sau khi ghi/flush document URI.
   Không nhận downgrade `flutter_secure_storage_windows`/`win32` chỉ để dùng một
   file picker khác.
10. Open/save/share được bao trong in-process `SystemUiInteractionGuard`. Privacy
    Shield vẫn che nội dung, nhưng app-lock không redirect/dispose route trong
    lúc system UI do app chủ động mở còn chờ kết quả. Guard release bằng `finally`;
    background ngoài operation vẫn relock theo policy cũ.

## Phương án đã cân nhắc

### Dùng PBKDF2 để có API đơn giản hơn

Không chọn. Argon2id có memory cost chống password cracking tốt hơn và là lựa
chọn hiện hành của
[OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
và [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.html) cho password-based
key derivation.

### Tái sử dụng cloud `VaultCipher`

Không chọn. Cloud envelope bind Supabase user/revision và data key ngẫu nhiên;
file portable cần password KDF, metadata cost riêng và không phụ thuộc backend.

### Mã hóa từng account rồi restore lần lượt

Không chọn. Cách này tạo partial restore, khó verify toàn snapshot và mất ordering.
Một authenticated payload + một COW replacement commit tạo boundary rõ hơn.

### Merge account từ file vào vault

Không chọn cho v1. “Restore” cần tái lập exact snapshot, giữ stable ID và order.
Merge/dedupe vẫn là semantics của QR import, không được âm thầm áp dụng cho backup.

### Cho phép restore ngay sau khi decrypt

Không chọn. AEAD chứng minh file/password hợp lệ nhưng không chứng minh người dùng
muốn thay vault hiện tại; preview và destructive confirmation là hai bước riêng.

## Hệ quả

### Tích cực

- Backup offline portable, backend-blind và giữ đủ stable ID/TOTP semantics.
- File/version/KDF metadata đủ để decoder tương lai tiếp tục mở v1.
- Tamper/wrong password/corrupt payload fail trước local mutation.
- Restore dùng atomicity đã được kiểm thử của local vault thay vì tạo persistence
  path thứ hai.

### Tiêu cực

- Password bị quên đồng nghĩa file không thể khôi phục.
- KDF tạo độ trễ và memory peak có chủ đích, đặc biệt trên thiết bị cũ/Web.
- Dart/Flutter không bảo đảm zeroize mọi bản sao `String` hoặc GC-managed memory.
- Thành công save trên Web chỉ chứng minh download đã được browser khởi tạo, không
  chứng minh người dùng giữ file đến đâu.
- iOS share result vẫn phụ thuộc semantics của provider được chọn; Android native
  document save có stronger success boundary nhưng không chứng minh retention lâu
  dài sau khi app đã ghi file.

### Rủi ro

- Password yếu vẫn có thể bị brute-force offline; UI bắt tối thiểu 12 code point
  nhưng không biến password thành entropy ngẫu nhiên.
- File picker Web phải load file vào memory trước khi app kiểm tra 8 MiB; đây là
  giới hạn còn lại của plugin/browser boundary.
- Sau restore thành công, generation cũ chỉ là internal rollback candidate chứ
  chưa phải nút undo user-facing.

## Bảo mật và quyền riêng tư

Không log exception gốc từ crypto/parser/file plugin. Password dùng nguyên văn,
không trim/normalize; UI giải thích điều này và không persist. Buffer tạm có thể
zeroize được sẽ bị ghi đè best-effort, nhưng không hứa memory erasure tuyệt đối.
Filename, issuer và account name có thể là metadata riêng tư; chỉ filename gợi ý
do app tạo và preview nội bộ được hiển thị.

## Dữ liệu và compatibility

Không đổi `AuthenticatorAccount`, local vault v2, encrypted cloud snapshot hoặc
Supabase contract. File v1 giữ exact account fields và order. Decoder tương lai
phải tiếp tục nhận v1 hoặc cung cấp migration explicit; encoder có thể tăng KDF
cost trong bound mà không đổi schema.

## Xác minh

- Known round-trip giữ ID/order/Unicode/custom algorithm/digits/period.
- Wrong password, salt/nonce/KDF/ciphertext/tag/payload tamper và future version
  đều fail closed.
- KDF resource bound, file/account/field limit và duplicate ID.
- BLoC cancel/timeout/lifecycle không gọi replacement; confirmed restore gọi đúng
  một replacement; injected storage commit failure giữ active snapshot.
- UI password confirm, preview không secret, typed destructive confirmation,
  small viewport/text scale và semantics redaction.
- `scripts/agent/check.sh full` và build platform đại diện.

## Rollout

1. Phát hành file v1 và giữ QR import/export là portability surface riêng.
2. Đo thời gian/memory Argon2id trên physical Android/iOS đại diện; chỉ tăng cost
   encoder ở release sau khi vẫn giữ decoder v1.
3. Kiểm thử backup → clean install → restore trên Android/iOS/macOS; Windows/Linux
   chạy qua CI artifact trước khi gọi production-ready.
4. Nếu plugin save/open lỗi trên một platform, ẩn capability platform đó trong
   patch release; không fallback sang plaintext file.

## Tham chiếu implementation

- [`cryptography` 2.9.0](https://pub.dev/packages/cryptography): Argon2id v19 và
  AES-GCM.
- [`file_selector` 1.1.0](https://pub.dev/packages/file_selector): system open
  trên sáu target, save location trên desktop và browser file abstraction.
- [`share_plus` 13.3.0](https://pub.dev/packages/share_plus): system share sheet
  cho encrypted file trên iOS.
- Android Storage Access Framework `ACTION_CREATE_DOCUMENT`: native local/provider
  save boundary qua `MainActivity`.
