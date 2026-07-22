# ADR-0008: Chỉ cho auth session còn active truy cập encrypted vault

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

Supabase `signOut(scope: others)` hủy refresh token/session khác nhưng access JWT
đã cấp vẫn hợp lệ tới `exp`. Chỉ dựa vào owner RLS với `auth.uid()` tạo một khoảng
thời gian mà session vừa revoke vẫn có thể đọc hoặc publish encrypted snapshot.
Với authenticator vault, khoảng này không phù hợp cho incident response sau khi
thiết bị bị mất hoặc nghi compromise.

DEK rotation thu hồi khả năng decrypt current snapshot của client chỉ giữ key cũ,
nhưng không tự thu hồi authorization của Supabase session. Hai control phải tách
biệt và có thể dùng liên tiếp.

## Quyết định

- Logout thông thường gọi rõ scope `local` và giữ local vault/app lock.
- Settings dùng `SessionSecurityBloc` để gọi scope `others`. Session, local vault
  và DEK của thiết bị hiện tại không đổi.
- Migration tạo `private.is_current_auth_session_active()` dạng `SECURITY DEFINER`.
  Helper chỉ true khi JWT `session_id` tồn tại trong `auth.sessions`, thuộc cùng
  `auth.uid()` và chưa qua optional `not_after`.
- Owner SELECT policy của `encrypted_vault_snapshots` và
  `publish_encrypted_vault_snapshot` đều bắt buộc helper này pass.
- Client không được đọc danh sách `auth.sessions`, không nhận service-role key và
  chưa mô tả action này là revoke riêng từng thiết bị.
- Incident flow được hướng dẫn: xoay vault key trên thiết bị tin cậy, sau đó bulk
  revoke mọi session khác.

## Phương án đã cân nhắc

### Chờ access JWT tự hết hạn

Không chọn vì production JWT TTL hiện là 3.600 giây. Refresh token bị hủy nhưng
encrypted vault vẫn có residual authorization window không cần thiết.

### Hạ JWT TTL toàn stack

Không chọn làm control chính vì ảnh hưởng mọi workload, tăng refresh traffic và
vẫn không tạo immediate revocation. TTL vẫn là defense-in-depth cho API khác.

### Device registry và device-specific wrapped key ngay lập tức

Đây là hướng mạnh hơn cho revoke chọn lọc nhưng cần persisted device identity,
key migration/recovery UX và lifecycle cleanup mới. Giữ là hạng mục sau; không
trì hoãn bulk server-side revocation đang có semantics rõ.

## Hệ quả

### Tích cực

- Session đã bị xóa khỏi `auth.sessions` mất quyền encrypted vault ngay cả khi JWT
  còn hợp lệ về chữ ký/thời hạn.
- Session hiện tại tiếp tục hoạt động; local TOTP vault và DEK không bị mutate.
- Lookup theo primary key `auth.sessions.id`, không cần device list ở client.

### Tiêu cực

- RLS SELECT của session revoked trả collection rỗng thay vì lỗi explicit; RPC trả
  `42501`/`session_revoked` để write path phân biệt được.
- Contract phụ thuộc schema `auth.sessions` và claim `session_id`; mọi upgrade
  Supabase Auth phải chạy lại migration/remote/restore contract.
- Control chỉ áp dụng encrypted vault. API khác vẫn theo policy/session semantics
  riêng của subsystem đó.

### Rủi ro

- Client bị kiểm soát có thể race publish trước khi trusted device hoàn tất revoke;
  optimistic revision giảm silent overwrite nhưng không loại bỏ denial-of-service.
- Bulk revoke không cho chọn một thiết bị cụ thể và không crypto-erase backup cũ.

## Bảo mật và quyền riêng tư

Helper không trả session row, IP, user-agent hoặc token; chỉ trả boolean. Function
nằm ngoài exposed API schema, revoke quyền `public`/`anon`, chỉ grant execute cho
`authenticated`. RPC vẫn lấy owner từ `auth.uid()`, không nhận user/session ID do
client truyền.

## Dữ liệu và compatibility

Migration không thêm/xóa encrypted row và không đổi envelope format. Nó thay RLS
policy/RPC cùng một private helper. Client cũ có JWT session chuẩn tiếp tục hoạt
động; token thiếu `session_id` fail closed.

Rollback giữ table/data, phục hồi policy/RPC từ migration `20260718190000`, sau đó
mới drop helper nếu không còn dependency. Hệ quả rollback phải được chấp nhận rõ:
JWT của session vừa revoke có thể truy cập vault tới `exp`.

## Xác minh

- PostgreSQL ephemeral test xóa row session, chứng minh RLS trả 0 và RPC fail;
  session mới vẫn tiếp tục monotonic revision.
- Production remote contract 20/20: hai session cùng user, revoke session cũ,
  session cũ bị chặn read/write và session hiện tại vẫn hoạt động.
- Health/restore harness xác minh helper `SECURITY DEFINER`, policy dependency,
  `FORCE RLS` và full restore.
- Flutter repository/BLoC/widget tests xác minh typed failure, confirmation và
  in-progress behavior.

## Cập nhật triển khai — 22-07-2026

Device registry và device-specific wrap đã được bổ sung sau ADR này, nhưng generic
vault-key rotation hiện cấp wrap mới cho mọi active device có membership proof hợp
lệ. Vì vậy flow “xoay vault key rồi bulk revoke” phía trên chỉ kết hợp rotation và
authorization revoke; nó **không** cryptographically exclude riêng thiết bị mục
tiêu và không remote-wipe local vault. Current encrypted remote suite có 36 check;
20/20 phía trên là evidence lịch sử của active-session rollout ban đầu.

## Rollout

1. Tạo verified backup trước migration.
2. Rehearse isolated PostgreSQL migration/session deletion.
3. Apply bằng owner `supabase_admin` trong transaction.
4. Chạy remote contract và xác nhận test user/row được cleanup.
5. Cập nhật health/restore harness; tạo backup mới và full restore rehearsal.
6. Ship client action sau khi full gate và CI pass.
