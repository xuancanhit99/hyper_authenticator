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

## Xoay vault encryption key đã triển khai

Thiết bị đang giữ DEK hợp lệ có thể sinh **DEK mới và recovery key mới** trong
memory. Client decrypt snapshot remote hiện tại bằng DEK cũ, re-encrypt cùng
plaintext bằng DEK mới ở revision kế tiếp và atomic publish ciphertext cùng
wrapped DEK mới. Chỉ sau read-after-write verification client mới thay DEK trong
secure storage và cập nhật last-seen revision.

- User phải xác nhận đã lưu recovery key mới trước publish.
- Hủy hoặc revision conflict giữ nguyên DEK, recovery key và snapshot cũ.
- Thiết bị chỉ giữ DEK cũ không decrypt được current snapshot và chuyển sang flow
  recovery; đây là bulk cryptographic read revocation cho client tuân thủ.
- Lỗi transport sau request, lỗi verify hoặc lỗi persist DEK là trạng thái mơ hồ:
  metadata không được nâng revision, UI bắt buộc giữ recovery key mới và recovery
  lại nếu inspect yêu cầu.
- Rotation không đổi local account snapshot. Local mutation chưa sync vẫn còn và
  được xử lý bởi conflict/sync flow ở lần tiếp theo.
- Sau rotation, một phiên tin cậy có thể targeted revoke phiên đã đăng ký hoặc
  bulk revoke mọi Supabase session khác; RLS/RPC active-session guard chặn session
  đã revoke. Device registry không phải device-specific key wrap/permanent ban.
  Trong khoảng trước revoke, client bị kiểm soát vẫn có thể gửi ciphertext tùy ý
  qua RPC.
- Backup lịch sử vẫn có ciphertext/wrapped DEK cũ. Xoay key không crypto-erase
  backup đã tạo và không làm thiết bị cũ quên DEK plaintext đã giữ.

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
- Remote contract: 20 checks cho anonymous/RLS/two-user/revision/RPC, atomic thay
  ciphertext + wrapped key và hai-session revoke enforcement.
- Device registry remote contract dùng isolated users để khóa server-derived
  current marker, no-direct-access, cross-tenant reject và targeted revoke.
- Android Pixel AVD E2E: Supabase login, setup vault rỗng revision 1, xoay recovery
  key tới revision 2, xoay DEK + recovery key tới revision 3, xóa app data để mô
  phỏng thiết bị mới rồi recovery thành công về revision 3; authenticated RLS read
  xác nhận remote và test user/row được xóa sau kiểm tra.
- Android Pixel AVD session smoke: isolated user có hai auth session, client SDK
  bulk revoke xuống một session, current session vẫn authenticated; cleanup pass.
- Device registry production cho phép list/targeted session revoke nhưng chưa đổi
  key hierarchy. HPKE Base primitive staged đã khớp official RFC 9180 vector cho
  AES-128-GCM và AES-256-GCM; device key store/proof test pass nhưng chưa inject,
  chưa có schema/RPC và không phải runtime capability.
- Release plaintext guard và DI generation test path.

## Khoảng trống đã biết

- Device registry và targeted auth-session revoke đã deploy. Device-specific key
  wrap mới ở trạng thái ADR đề xuất + primitive staged; chưa có enrollment,
  atomic wrap-set rotation, runtime recovery hoặc production schema.
- Trusted-device/QR transfer.
- Tombstone hoặc history ngoài một current snapshot.
- Browser E2EE threat model.
- Independent security review và physical two-device E2E test.
