# Chính sách quyền riêng tư — bản dự thảo phát hành

Cập nhật: 18 tháng 7 năm 2026.

Tài liệu này phản ánh behavior đã triển khai. Trước store submission, owner phải
điền tên pháp nhân/nhà phát hành, kênh support và host nội dung tại URL HTTPS công khai.

## Dữ liệu ứng dụng xử lý

Hyper Authenticator xử lý tên nhà cung cấp, tên tài khoản, TOTP secret và tham số
TOTP để tạo mã xác thực trên thiết bị. Nếu người dùng đăng nhập, Supabase Auth xử
lý email, password verifier/session và audit/security metadata cần cho xác thực.

## Lưu trữ local

TOTP account được lưu trong platform secure storage của thiết bị/browser profile.
Ứng dụng không gửi plaintext TOTP secret tới analytics hoặc log. Logout Supabase
không tự động xóa local authenticator vault.

## Encrypted cloud sync tùy chọn

Trên Android, iOS, macOS, Windows và Linux, người dùng có thể bật encrypted cloud
sync. Trước khi rời thiết bị, account snapshot được mã hóa AES-256-GCM. Backend lưu
ciphertext, wrapped key, revision và timestamp; backend không nhận recovery key
hoặc DEK plaintext.

Cloud sync hiện tắt trên Web. Password reset không khôi phục E2EE vault; người dùng
phải giữ recovery key hoặc thiết bị còn key. Mất cả hai có thể làm mất quyền khôi phục.

## Mục đích xử lý

- tạo mã TOTP theo yêu cầu người dùng;
- bảo vệ local access bằng OS authentication khi được bật;
- đăng ký/đăng nhập/khôi phục Supabase account;
- đồng bộ encrypted snapshot khi người dùng chủ động bật;
- bảo mật, chống lạm dụng, backup và vận hành dịch vụ.

## Chia sẻ và bên xử lý

Deployment hiện dùng Supabase self-hosted do nhà phát hành vận hành. Hạ tầng mạng,
email và hosting có thể xử lý metadata kỹ thuật cần để cung cấp dịch vụ. Danh sách
nhà cung cấp/pháp nhân cụ thể phải được owner bổ sung trước public release.

Không bán TOTP secret hoặc encrypted vault. Không dùng TOTP secret cho quảng cáo.

## Retention và xóa

Local data tồn tại tới khi người dùng xóa account/app data theo platform. Remote
encrypted snapshot gắn với Supabase user và được xóa khi backend account bị xóa.
Backup vận hành có retention giới hạn; bản production hiện giữ 7 local backup và
14 encrypted off-host copy, sau đó được rotation tự động.

Ứng dụng chưa có self-service account deletion UI. Trước store submission, owner
phải cung cấp support channel/quy trình xác minh yêu cầu truy cập hoặc xóa account.

## Bảo mật

Ứng dụng dùng platform secure storage, TLS, RLS, AES-256-GCM encrypted snapshot,
verified backup và restore rehearsal. Không có hệ thống nào bảo mật tuyệt đối; người
dùng phải bảo vệ thiết bị và recovery key, đồng thời rotate TOTP nếu nghi bị lộ.

## Quyền và liên hệ

Quyền riêng tư cụ thể phụ thuộc nơi người dùng cư trú. Để hỏi hoặc yêu cầu xử lý dữ
liệu, dùng kênh support/privacy do nhà phát hành công bố tại trang store/website.

**Release blocker:** chưa điền pháp nhân, jurisdiction, support/privacy email, data
processor list và URL public. Không dùng bản dự thảo này để tuyên bố legal compliance.
