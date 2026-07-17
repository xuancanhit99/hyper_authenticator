# ADR-0003: Local vault hoạt động offline và độc lập Supabase identity

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế: P-001, P-004
- Bị thay thế bởi:

## Bối cảnh

TOTP là chức năng local cốt lõi nhưng router hiện bắt buộc Supabase session. Logout
giữ secret local, vì vậy dùng Supabase identity làm quyền sở hữu vault vừa chặn
offline vừa tạo ngữ nghĩa mơ hồ khi nhiều account đăng nhập trên cùng thiết bị.

## Quyết định

Local vault thuộc installation/profile local, không thuộc Supabase user. Người dùng
có thể mở, thêm và dùng TOTP không cần network hoặc login. App lock bảo vệ vault
độc lập với trạng thái Supabase. Supabase login chỉ mở các tính năng cloud; logout
không xóa vault, không tắt app lock và không đổi namespace local.

## Phương án đã cân nhắc

### Bắt buộc Supabase login

Dễ gắn remote owner nhưng làm TOTP phụ thuộc dịch vụ bên ngoài và không giải quyết
việc secret local vẫn tồn tại sau logout.

### Namespace local theo Supabase user

Tách account rõ hơn nhưng người dùng có thể mất quyền truy cập TOTP khi session
hết hạn hoặc đăng nhập nhầm. Không chọn cho core authenticator.

## Hệ quả

### Tích cực

- TOTP dùng được offline và khi Supabase gián đoạn.
- Auth outage không khóa người dùng khỏi mã xác thực.
- App lock có lifecycle riêng, không bị logout vô hiệu hóa.

### Tiêu cực

- Nhiều Supabase user trên cùng OS profile nhìn cùng local vault sau khi unlock.
- Cloud sync cần cảnh báo account đang kết nối và không suy luận local ownership.

### Rủi ro

- Thiết bị dùng chung cần OS account/app lock; app không cung cấp multi-profile local
  trong quyết định này.

## Bảo mật và quyền riêng tư

Supabase session không phải key mở local vault. Secure storage và app lock vẫn là
boundary local. Login/logout không được xóa, export hoặc upload secret ngầm.

## Dữ liệu và compatibility

Không đổi format local storage v2. Migration chỉ đổi routing và preference logout;
legacy biometric preference được giữ.

## Xác minh

Unit test redirect cho unauthenticated main, app-lock fail closed và public auth
route; AuthBloc test logout giữ biometric preference.

## Rollout

1. Tách redirect policy khỏi Supabase requirement.
2. Hiển thị Sign in/Sign out theo session trong Settings.
3. Giữ cloud control disabled nếu chưa login/E2EE chưa ready.
