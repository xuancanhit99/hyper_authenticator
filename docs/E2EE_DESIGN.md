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
- Trước khi tạo bất kỳ wrap generation mới nào, client dùng DEK hiện tại để verify
  current-generation wrap + membership proof của mọi active device. Entry thiếu,
  stale hoặc giả làm preparation fail closed trước publish.
- Generic rotation cấp wrap mới cho **toàn bộ** active device đã verify. Settings
  chưa có per-device cryptographic exclusion; backend exact-set rotation có thể
  loại ID rõ ràng nhưng client flow hiện gửi exclusion rỗng. Vì vậy generic rotation
  không phải cryptographic device revoke.
- Thiết bị chỉ giữ DEK cũ không decrypt trực tiếp current snapshot; client đọc
  exact HPKE wrap generation mới, verify membership proof, decrypt snapshot rồi
  mới persist DEK. Thiết bị không có wrap do explicit exclusion, mất private key
  hoặc có wrap sai phải chuyển sang HA1 recovery.
- Lỗi transport sau request, lỗi verify hoặc lỗi persist DEK là trạng thái mơ hồ:
  metadata không được nâng revision, UI bắt buộc giữ recovery key mới và recovery
  lại nếu inspect yêu cầu.
- Rotation không đổi local account snapshot. Local mutation chưa sync vẫn còn và
  được xử lý bởi conflict/sync flow ở lần tiếp theo.
- Sau rotation, một phiên tin cậy có thể targeted revoke phiên đã đăng ký hoặc
  bulk revoke mọi Supabase session khác; RLS/RPC active-session guard chặn session
  đã revoke. Đây chỉ là authorization revoke: không remote-wipe local vault, không
  làm target quên DEK và không tự loại device key khỏi rotation tiếp theo. Device
  registry không phải permanent ban. Client đã bị kiểm soát có thể giữ dữ liệu/key
  từng tải xuống; cryptographic exclusion cho người dùng vẫn là khoảng trống.
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

## Loại bỏ đường sync plaintext

Plaintext datasource, mapper, repository và use case đã bị xóa khỏi client;
`ALLOW_INSECURE_PLAINTEXT_SYNC` chỉ còn là poison sentinel và mọi build từ chối
`true`. Migration loại bỏ cuối cùng xử lý `public.synced_accounts` theo
fail-closed contract:

1. operator tạo fresh full backup, checksum và encrypted/off-host copy;
2. inventory row count mà không đọc/log secret;
3. nếu bảng còn row, migration abort nguyên transaction với
   `plaintext_legacy_rows_present`; table/data vẫn nguyên để migrate thủ công;
4. chỉ khi row count bằng `0`, drop table không `CASCADE`;
5. re-apply khi table đã vắng là idempotent;
6. post-check xác minh PostgREST không còn expose resource và restore rehearsal
   phải chạy lại migration loại bỏ trước khi nhận traffic.

Rollback client không bật lại plaintext sync. Nếu phải khôi phục database cũ,
operator dùng backup tương thích trong maintenance window, hoàn tất migration data
rồi chạy lại zero-row retirement trước khi mở dịch vụ.

## Bằng chứng

- Crypto/key-store/model tests: tamper, wrong user/key, future format, round-trip.
- Use-case tests: setup/cancel/recovery/conflict/publish conflict/read-after-write.
- Remote contract: 36 checks cho anonymous/RLS/two-user/revision/RPC, expected-revision `NULL`, legacy
  update cutoff, native enroll/self-wrap/confirm, device-bound v2 publish, atomic
  thay ciphertext + wrapped key và two-session revoke enforcement.
- Device registry remote contract dùng isolated users để khóa server-derived
  current marker, no-direct-access, cross-tenant reject và targeted revoke.
- Android Pixel AVD E2E: Supabase login, setup vault rỗng revision 1, xoay recovery
  key tới revision 2, xoay DEK + recovery key tới revision 3, xóa app data để mô
  phỏng thiết bị mới rồi recovery thành công về revision 3; authenticated RLS read
  xác nhận remote và test user/row được xóa sau kiểm tra.
- Android Pixel AVD session smoke: isolated user có hai auth session, client SDK
  bulk revoke xuống một session, current session vẫn authenticated; cleanup pass.
- Device registry production cho phép list/targeted session revoke nhưng chưa đổi
  key hierarchy. HPKE Base primitive, client coordinator và additive migration/RPC
  production đã pass official vectors cùng PostgreSQL two-phase enrollment,
  server-only DEK verifier và exact-set rotation/exclusion contract. Generic client
  chưa cung cấp exclusion và luôn giữ toàn bộ active device đã verify. Schema đã
  deploy production và pass Linux isolated client runtime tới revision 4.
  Android AVD/iOS Simulator còn pass two-session exact rotation: secondary giữ
  DEK cũ tự unwrap generation mới mà không dùng HA1.
- Rotation regression chứng minh proof giả/stale của bất kỳ active device nào làm
  fail trước khi next-generation wrap được tạo.
- PostgreSQL hardening contract chứng minh legacy update và v2 protocol
  `0` bị từ chối, v2 dùng row lock `FOR UPDATE`, còn protocol `1` với exact binding
  tiếp tục publish được.
- Plaintext retirement contract chứng minh non-empty abort/rollback nguyên vẹn,
  empty drop và re-apply idempotent.

## Khoảng trống đã biết

- Device registry và targeted auth-session revoke đã deploy. Device-specific key
  wrap có ADR được duyệt, server production và Linux/Android/iOS lost-device-key
  recovery/rotation runtime. Per-device exclusion mới là khả năng backend;
  Settings/generic rotation chưa cung cấp lựa chọn cho người dùng. Còn physical two-device và
  independent review.
- Trusted-device/QR transfer.
- Tombstone hoặc history ngoài một current snapshot.
- Browser E2EE threat model.
- Independent security review và physical two-device E2E test.
