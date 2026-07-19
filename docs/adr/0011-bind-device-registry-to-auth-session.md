# ADR-0011: Bind device registry với auth session do server xác định

- Trạng thái: Chấp nhận
- Ngày: 2026-07-19
- Owner: canhvx
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

Bulk `SignOutScope.others` xử lý incident tốt nhưng không cho người dùng nhận diện
và đăng xuất riêng một phiên. Client không được đọc trực tiếp `auth.sessions`, và
không thể được tin cậy để gửi `user_id`/`session_id` mục tiêu vì hai field này là
authorization boundary.

Device-specific DEK wrap sẽ cần device key pair, enrollment/recovery/migration và
rotation protocol riêng. Không nên gắn nhãn control session-level hiện tại là
cryptographic device revocation.

## Quyết định

- Tạo `authenticator_device_sessions`; mỗi row bind một opaque registration ID với
  đúng `auth.sessions.id` lấy từ JWT hiện tại và `auth.uid()`.
- Client gửi installation UUID, nhãn và platform để hiển thị. Installation UUID
  nằm trong SharedPreferences, không phải credential và không cấp quyền.
- Table bật + force RLS, không grant direct access cho `authenticated`; ba
  `SECURITY DEFINER` RPC là API duy nhất.
- List chỉ trả registered session còn active của current user, không trả session
  ID, token, IP hoặc user agent. Current marker do server so sánh session ID.
- Targeted revoke nhận opaque registration ID, khóa row, cấm current session rồi
  xóa đúng `auth.sessions` row thuộc current user. Active-session guard hiện có
  làm access JWT mục tiêu mất quyền encrypted vault ngay.
- Revoked/inactive metadata quá 30 ngày được prune khi một phiên hợp lệ đăng ký.
- UI giữ bulk revoke để xử lý session cũ/chưa đăng ký và mô tả targeted action là
  đăng xuất có thể đăng nhập lại, không phải permanent device ban.

## Phương án đã cân nhắc

### Cho client gửi hoặc đọc raw session ID

Không chọn. Nó mở rộng metadata nhạy cảm không cần thiết và dễ tạo authorization
bug. Opaque registration ID cùng server-derived session binding đủ cho UX.

### Gom mọi session theo installation UUID rồi revoke cả nhóm

Không chọn vì installation UUID do client cung cấp, có thể bị clone/spoof và không
được dùng để quyết định current/target authorization. Mỗi registry row tương ứng
một server auth session; installation ID chỉ là display metadata.

### Chờ device-specific key pair/wrap hoàn chỉnh

Không chọn vì targeted auth revocation mang giá trị độc lập và dùng lại immediate
active-session enforcement đã deploy. Crypto enrollment vẫn là milestone riêng.

## Hệ quả

### Tích cực

- Người dùng có thể đăng xuất một phiên đã nhận diện mà không hủy mọi phiên khác.
- Cross-tenant và self-revoke bị server chặn, không phụ thuộc UI.
- Client không nhận raw auth session metadata và local/cloud vault không bị mutate.

### Tiêu cực

- Session cũ chưa chạy client mới không xuất hiện; bulk revoke vẫn cần thiết.
- Nhãn platform tổng quát không xác định model máy và một cài đặt có thể xuất hiện
  nhiều lần nếu tạo nhiều session.
- Re-login tạo session mới; đây không phải denylist thiết bị.

### Rủi ro

- Transport fail sau request có thể tạo trạng thái revoke mơ hồ; UI yêu cầu tải
  lại danh sách thay vì retry mù.
- Session compromise vẫn có thể tự sửa display metadata của chính session đó,
  nhưng không thể đổi server-derived owner/session/current marker.
- Xóa `auth.sessions` phụ thuộc contract nội bộ GoTrue; migration/remote/restore
  probe phải chạy lại sau mỗi Supabase Auth upgrade.

## Bảo mật và quyền riêng tư

Registry không chứa token, IP, user agent, TOTP data, DEK hoặc recovery key.
Registration/installation ID là pseudonymous metadata và được redact khỏi BLoC/
entity string representation. RPC lấy owner/session từ signed JWT, kiểm tra active
session và trả not-found cho cross-tenant ID.

Thu hồi session chỉ cắt cloud authorization; local TOTP trên thiết bị mục tiêu vẫn
tồn tại. Nếu thiết bị có DEK hoặc backup cũ, người dùng vẫn cần vault-key rotation
và incident response phù hợp.

## Dữ liệu và compatibility

Migration additive, không đổi encrypted envelope/snapshot và không đụng local
vault. Client cũ tiếp tục hoạt động nhưng không tự đăng ký. Rollback bỏ client UI,
khôi phục health probe rồi drop ba RPC/table bằng migration mới; session đã thu
hồi không thể phục hồi và người dùng đăng nhập lại.

## Xác minh

- Ephemeral PostgreSQL contract: FORCE RLS/no direct SELECT, current-only marker,
  self/cross-tenant reject và target deletion chặn publish.
- Remote isolated-user contract: two-user/two-session register/list, no metadata
  leak, targeted refresh/JWT revoke và current survival.
- Flutter model/store/BLoC/widget test: UUID round-trip, typed state, double-submit,
  confirmation, current protection và identifier redaction.
- Health/restore rehearsal probe table, privilege và ba security-definer RPC.

## Rollout

1. Full verified backup và off-host encrypted copy.
2. Chạy migration contract trong PostgreSQL tạm.
3. Apply additive migration bằng `supabase_admin`.
4. Chạy remote device contract, health và cleanup probe.
5. Tạo backup mới; restore rehearsal phải thấy registry guard.
6. Chỉ sau đó phát hành client UI.
