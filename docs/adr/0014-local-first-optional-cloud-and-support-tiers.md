# ADR-0014: Local-first, cloud tùy chọn và support tier

- Trạng thái: Chấp nhận
- Ngày: 2026-07-23
- Owner: HyperZ
- Thay thế: một phần A-003, A-006, A-007 và P-006
- Bị thay thế bởi:

## Bối cảnh

TOTP local là chức năng cốt lõi nhưng bootstrap trước đây luôn yêu cầu cấu hình
Supabase. Settings cũng đưa các thao tác revision, device session và key rotation
ra UI chính, khiến một ứng dụng authenticator trông giống console vận hành cloud.
Điều này làm tăng coupling, số state owner và khả năng người dùng hiểu nhầm rằng
phải đăng nhập mới dùng được TOTP.

Encrypted snapshot/device-wrap protocol đã deploy và có contract bảo mật riêng.
Việc đơn giản hóa sản phẩm không được làm mất local vault, đổi schema hoặc hạ
thấp fail-closed behavior của protocol đó.

## Quyết định

1. TOTP local, import QR và app lock là product core, hoạt động không cần tài
   khoản hoặc Supabase configuration.
2. Cloud là capability tùy chọn. Chỉ khi có đủ Supabase URL, publishable key và
   recovery URL hợp lệ thì app mới khởi tạo Supabase và mở auth/backup UI.
3. Cloud UX chính được gọi là **backup cloud mã hóa đầu cuối** và do người dùng
   kích hoạt. Revision, protocol và key generation là chi tiết kỹ thuật, không
   hiển thị trong luồng phổ thông.
4. Recovery-key rotation nằm trong phần bảo mật nâng cao. Device registry,
   targeted session revoke và generic vault-key rotation không còn nằm trong
   primary Settings, nhưng backend/data contract được giữ để hardening hoặc UI
   chuyên biệt về sau.
5. Theme dùng một `ThemeCubit`; feature state tiếp tục dùng BLoC. Preference chỉ
   lưu setting không nhạy cảm đang có giá trị runtime; bỏ Remember Me vì Supabase
   đã sở hữu session persistence.
6. Support tier hiện tại:
   - Android, iOS và macOS: native core; release còn phụ thuộc credential/device
     evidence tương ứng.
   - Windows và Linux: desktop core; camera QR phụ thuộc capability hiện có.
   - Web: local TOTP surface với trust boundary yếu hơn native; không bật E2EE
     backup.

## Phương án đã cân nhắc

### Bắt buộc Supabase cho mọi lần khởi động

Dễ giả định một identity duy nhất nhưng làm mất offline-first, tăng blast radius
khi backend lỗi và không phù hợp chức năng authenticator cốt lõi.

### Xóa toàn bộ cloud/E2EE

Giảm source đáng kể nhưng phá vỡ protocol đã deploy, khả năng recovery đa thiết
bị và investment kiểm thử hiện có. Phương án này không tương xứng với lợi ích.

### Giữ toàn bộ advanced cloud operation trong Settings

Không đổi code nhưng khiến người dùng phải hiểu session, revision và key rotation.
Những thao tác đó không thuộc luồng TOTP hằng ngày.

## Hệ quả

### Tích cực

- Local app khởi động và tạo TOTP khi cloud chưa cấu hình hoặc tạm unavailable.
- UI chính nhỏ hơn và dùng từ vựng theo tác vụ người dùng.
- Một state pattern cho theme; ít dependency và state owner trùng.
- Có thể phát hành bản local-only mà không embed Supabase public config.

### Tiêu cực

- DI vẫn cần một inert Supabase client nội bộ để giữ graph hiện tại cho auth
  repository; client này không được gọi khi capability cloud tắt.
- Advanced cloud code vẫn tồn tại và cần contract test dù không ở primary UI.
- Bản build local-only không thể bật cloud sau runtime; phải build lại với public
  compile-time config.

### Rủi ro

- Partial config có thể tạo trạng thái nửa cloud. Validator từ chối mọi tổ hợp
  thiếu URL/key/recovery.
- Route auth có thể bị deep link trong local-only build. Redirect policy đưa
  người dùng về local app.
- Ẩn advanced UI không đồng nghĩa xóa server risk; migration/RLS/E2EE gate vẫn
  bắt buộc cho thay đổi backend.

## Bảo mật và quyền riêng tư

Không secret, service-role key hoặc SSH variable được đưa vào Flutter asset.
Local-only không khởi tạo network client. Cloud-enabled build vẫn chỉ nhận HTTPS
origin và public key; plaintext poison flag tiếp tục fail closed. QR export một
tài khoản bị gỡ khỏi primary UI vì nó tiết lộ full TOTP secret mà chưa có
reauthentication/export-session policy.

## Dữ liệu và compatibility

Không thay đổi serialized account, local vault COW format, secure-storage key,
encrypted envelope, Supabase schema/RPC hoặc key generation. Theme preference cũ
được đọc bởi `ThemeCubit`. Preference Remember Me không còn được dùng; Supabase
session storage không đổi.

## Xác minh

- Public-config tests cho local-only, partial config, release cloud config và
  plaintext poison.
- Router regression cho auth route trong local-only.
- Full Flutter test và PostgreSQL migration contract.
- Release Web build không config phải boot local shell, không render startup
  failure.

## Rollout

1. Đưa local-only bootstrap và route guard vào cùng release.
2. Đổi Settings/cloud copy và ẩn advanced operation khỏi primary UI.
3. Giữ backend migration/protocol nguyên trạng.
4. Theo dõi startup failure, auth deep link và local-vault regression.
5. Rollback bằng client revert; không rollback database.
