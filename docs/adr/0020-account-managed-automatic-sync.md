# ADR-0020: Đồng bộ tự động do tài khoản quản lý

- Trạng thái: Chấp nhận
- Ngày: 2026-08-04
- Owner: HyperZ
- Thay thế: ADR-0005, ADR-0019
- Bị thay thế bởi:

## Bối cảnh

Minimal E2EE yêu cầu người dùng tạo, lưu và nhập HA1 recovery key. Luồng này
không đạt mục tiêu product mới: dùng local bình thường khi chưa đăng nhập, còn
khi đăng nhập thì mã TOTP tự xuất hiện trên thiết bị mới và mọi thay đổi tự đồng
bộ tương tự Google Authenticator.

Thiết bị mới không thể giải mã client-side ciphertext nếu không có một secret
ngoài phiên đăng nhập. Vì vậy không thể đồng thời bỏ recovery key, giữ server
zero-knowledge và cho phép chỉ đăng nhập là khôi phục mã.

## Quyết định

Chuyển sang account-managed sync:

- chưa đăng nhập: local vault tiếp tục là nguồn dữ liệu duy nhất;
- đăng nhập: client tự đồng bộ các account thuộc Supabase user hiện hành;
- backend mã hóa payload TOTP khi lưu bằng Supabase Vault và chỉ trả plaintext
  qua authenticated `security definer` RPC đã kiểm tra `auth.uid()`;
- mỗi TOTP account là một remote record độc lập với stable UUID, revision và
  tombstone; xóa khi đăng nhập tạo tombstone để thiết bị offline không làm mã
  sống lại;
- local secure storage giữ metadata ownership/revision/fingerprint. Account chưa
  có owner được gắn với user đầu tiên đang đăng nhập; account đã thuộc user khác
  không bao giờ tự upload sang user hiện hành;
- mutation local luôn hoàn tất trước. Cloud lỗi không làm mất khả năng tạo mã;
  pending change được retry ở lần đồng bộ sau;
- logout dừng đồng bộ nhưng giữ nguyên local vault và ownership metadata.

Không giữ dual-write, fallback đọc Minimal E2EE, HA1 recovery UI hoặc encrypted
snapshot protocol cũ.

## Phương án đã cân nhắc

### Tiếp tục Minimal E2EE nhưng ẩn recovery key

Không khả thi trên thiết bị mới: nếu server và người dùng đều không giữ key thì
không có chủ thể nào có thể giải mã snapshot.

### Lưu payload trực tiếp trong bảng public

Đơn giản hơn nhưng database dump chứa TOTP plaintext. Không chọn.

### Một encrypted snapshot/user do server quản lý

Giảm số row nhưng làm merge/xóa offline phải thay cả vault và dễ tạo conflict
toàn cục. Per-account record cô lập mutation và cho phép tombstone.

## Hệ quả

### Tích cực

- Không còn setup/import recovery key hay conflict dialog thủ công.
- Đăng nhập trên thiết bị mới tự tải mã; thêm/sửa/xóa tự retry lên cloud.
- Một account lỗi không khóa toàn bộ vault.
- Offline/local-only vẫn hoạt động.

### Tiêu cực

- Đây không còn là E2EE/zero-knowledge. Backend có thể giải mã TOTP trong lúc
  thực thi RPC; compromise của database role/root key có thể lộ credential.
- Account local chưa có owner sẽ được user đăng nhập đầu tiên nhận ownership.
- Tombstone làm tăng dữ liệu và cần retention job riêng trước khi scale lớn.

## Bảo mật và quyền riêng tư

Payload trong table/backup phải là Vault ciphertext. Client chỉ dùng publishable
key; service-role key và Vault root key không được đưa vào app. RPC revoke khỏi
`anon`/`public`, kiểm tra `auth.uid()`, validate payload và giới hạn kích thước.
Không log payload, TOTP secret hoặc full `otpauth` URI.

## Dữ liệu và compatibility

Migration là breaking reset của remote sync contract: drop
`encrypted_vault_snapshots`/RPC cũ rồi tạo per-account records/RPC mới. Local
vault v2 không đổi. Client cũ mất khả năng cloud sync nhưng vẫn dùng local.
Không migrate ciphertext HA1 vì server không có recovery key; rollout chỉ được
deploy sau backup và xác nhận remote snapshot hiện tại không cần giữ.

## Failure behavior

- Pull/push lỗi: giữ local và pending metadata, hiển thị trạng thái retry được.
- Payload remote lỗi: không ghi đè local; sync báo lỗi an toàn.
- CAS conflict: pull revision mới rồi retry local pending mutation một lần; nếu
  vẫn conflict thì giữ pending cho lần sau.
- Xóa local đã commit nhưng cloud lỗi: tombstone intent tồn tại trong secure
  metadata và được retry.

## Rollback

Rollback client về local-only là an toàn; không cho client Minimal E2EE cũ ghi
vào schema mới. Rollback backend cần restore full backup cùng Vault root key.

## Rollout

1. Merge client/schema và cho full gate pass.
2. Audit production row count, tạo full backup, checksum và restore rehearsal.
3. Deploy migration trong maintenance window; chạy RLS/RPC contract test.
4. Phát hành client mới và theo dõi auth/sync failure không chứa credential.
