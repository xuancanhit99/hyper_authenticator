# ADR-0013: Loại bỏ plaintext sync và bắt buộc device-bound publish

- Trạng thái: Đã chấp nhận
- Ngày: 2026-07-22
- Owner: canhvx
- Thay thế một phần: ADR-0001, ADR-0005
- Bị thay thế bởi: —

## Bối cảnh

E2EE snapshot và device-specific HPKE wrap đã trở thành runtime path duy nhất,
nhưng schema `public.synced_accounts` vẫn cung cấp PostgREST CRUD cho TOTP secret
plaintext. Dù client release không inject bridge này, binary cũ hoặc JWT chưa hết
hạn vẫn có thể gọi API; hai kho cloud cũng có thể phân kỳ.

Sau khi device-wrap được bật, RPC v2 kiểm tra device binding. Tuy nhiên snapshot ở
protocol `0` vẫn từng được phép update, và hàm đọc protocol trước khi update mà
không khóa row, tạo cửa sổ TOCTOU với bước xác nhận device key.

Read-only production preflight tại thời điểm ra quyết định ghi nhận không có row
legacy cần migrate. Đây không thay thế fresh backup và zero-row preflight ngay
trước deploy. Việc giữ schema chỉ để rollback làm tăng attack surface và khiến
tài liệu/runtime contract khó hiểu.

## Quyết định

1. Migration retirement lấy `ACCESS EXCLUSIVE` lock, đặt `row_security=off` rồi
   kiểm tra `count(*)`; operator thiếu `BYPASSRLS` fail closed, còn bất kỳ row nào
   thì abort nguyên transaction với
   `plaintext_legacy_rows_present`. Chỉ bảng rỗng mới được drop, không dùng
   `CASCADE`.
2. Xóa plaintext data source, mapper, repository và use case khỏi client. Compile
   define `ALLOW_INSECURE_PLAINTEXT_SYNC` được giữ như poison/safety sentinel nhưng
   mọi build đều từ chối giá trị `true`.
3. Legacy encrypted publish RPC chỉ tạo revision `1`. Mọi update sau đó phải:
   enroll/confirm current device key, chuyển snapshot sang protocol `1`, rồi gọi v2.
4. RPC v2 xác minh auth session ở entry, sau đó khóa exact snapshot row bằng
   `FOR UPDATE`, kiểm tra revision, generation và protocol `1` trên row đã khóa,
   rồi xác minh active device binding trước update.
5. Rollback client không được bật lại plaintext. Rollback destructive migration
   dùng full backup đã xác minh và release/schema tương thích trong maintenance
   window.

## Hệ quả

### Tích cực sau rollout

- Không còn PostgREST table chứa TOTP secret plaintext hoặc client code có thể ghi nó.
- Old binary fail closed thay vì âm thầm tạo kho cloud song song.
- Protocol activation và publish được serialize; update không còn chạy trong trạng
  thái chuyển tiếp chưa có device binding.
- Fresh onboarding vẫn tạo được revision đầu tiên trước khi self-wrap/confirm.

### Tiêu cực

- Client cũ không thể update vault đã có revision; trên vault trống legacy RPC chỉ
  có thể tạo revision `1`, sau đó client phải nâng cấp để enroll device và publish.
- Nếu operator phát hiện row legacy, rollout dừng để backup/migration thủ công;
  không có auto-delete hoặc auto-encrypt vì client-side recovery key mới là nguồn
  quyền E2EE.
- Restore backup trước cutoff có thể chứa bảng plaintext; phải chạy migration và
  zero-row preflight lại trước khi đưa dịch vụ nhận traffic.

## Threat và failure behavior

- Migration không in row content; chỉ báo số lượng trong error detail.
- Table non-empty giữ nguyên sau failure nhờ transaction.
- V2 request protocol `0` trả lỗi trước mutation. Request revision/generation sai
  trả conflict; binding sai hoặc session revoke trả authorization failure.
- Cutoff không remote-wipe secret đã từng được tải xuống client/backup cũ.

## Xác minh

- PostgreSQL 17 contract: concurrent legacy writer được serialize, retirement
  trả exact SQLSTATE và giữ row; operator thiếu `BYPASSRLS` fail closed; empty
  drop nằm trong guarded branch; re-apply idempotent.
- Encrypted migration contract: expected revision `NULL`, legacy update và v2
  protocol `0` bị từ chối; function definition có row lock; protocol `1` với exact
  binding tiếp tục pass.
- Production cần fresh backup/checksum/off-host copy, zero-row preflight, apply hai
  migration, PostgREST table-absent contract, health và restore rehearsal.

## Trạng thái triển khai

Source client, migration và local regression contract đã hiện thực quyết định
này. Production deploy ngày 22-07-2026 có pre/post backup + encrypted off-host,
zero-row preflight, table-absent/36-check encrypted remote contract, health, full
restore và final zero-data audit. Corrective review còn có pre/post backup
`supabase-20260722T161217Z`/`supabase-20260722T161534Z`, restore và encrypted
off-host copy. Evidence chi tiết nằm trong
`docs/PROJECT_STATUS.md`; việc ADR được chấp nhận vẫn không tự thay thế các gate
này cho future restore hoặc instance khác.
