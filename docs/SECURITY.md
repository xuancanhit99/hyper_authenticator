# Mô hình bảo mật

## Trạng thái hiện tại

Dự án phải được xem là phần mềm alpha. Local storage dùng secure-storage abstraction, nhưng toàn hệ thống chưa cung cấp ranh giới backup hoặc sync đủ an toàn cho production.

Điểm quan trọng nhất: cloud sync hiện upload TOTP secret ở dạng có thể đọc.

## Asset cần bảo vệ

| Asset | Tác động khi bị lộ |
|---|---|
| TOTP `secretKey` | Kẻ tấn công có thể tạo yếu tố xác thực thứ hai |
| URI `otpauth` đầy đủ | Tương đương làm lộ secret được nhúng |
| Supabase session | Kẻ tấn công có thể truy cập hoặc sửa cloud snapshot của user |
| Email và tên người dùng | Rủi ro privacy và phishing |
| Nhãn tài khoản local | Lộ thông tin riêng tư và dịch vụ đang dùng |
| Encryption key hoặc recovery code tương lai | Giải mã hoặc khôi phục secret đã sync |

## Trust boundary

- Flutter process với FlutterSecureStorage.
- Flutter process với SharedPreferences.
- Flutter process với local authentication của OS.
- Flutter process với Supabase qua network.
- Supabase Auth với PostgreSQL RLS.
- Browser page khôi phục mật khẩu với Supabase.
- Build environment với client configuration được đóng gói.

Filter `user_id` phía client không phải authorization boundary. RLS policy đã deploy mới là boundary.

## Control đã triển khai

- JSON tài khoản TOTP được lưu qua FlutterSecureStorage.
- App lock giao việc xác minh cho `local_auth` và OS.
- Supabase Auth quản lý password verification và session.
- Repository boundary chuyển nhiều infrastructure exception thành typed failure.
- `.env` bị Git bỏ qua.
- Client dùng anon key và không cần server key.

Những control này không biến cloud secret dạng plaintext thành E2EE.

## Release blocker đã xác nhận

### Đồng bộ plaintext

`AuthenticatorAccount.toJson` có `secretKey`. Sync data source chèn map đó vào Supabase. Active path không có encryption, authentication tag, key derivation, key wrapping hoặc versioned envelope.

Bắt buộc trước cloud sync production:

- E2EE ADR được chấp nhận;
- encrypted payload có version;
- authenticated encryption;
- bootstrap key đa thiết bị;
- thiết kế recovery;
- migration từ mọi row plaintext;
- log và fixture đã redact;
- cryptographic test và integration test.

### Upload phá hủy và không atomic

Upload xóa toàn bộ row của user rồi chèn danh sách thay thế. Lỗi sau bước delete có thể xóa cloud copy.

Bắt buộc:

- database transaction hoặc versioned snapshot commit;
- optimistic concurrency hoặc compare-and-swap;
- retry idempotent;
- validation phía server;
- recovery sau write bị gián đoạn;
- xác nhận rõ thao tác phá hủy và UI an toàn cho audit.

### Xóa dữ liệu khi logout

`AuthBloc` sign out rồi gọi `deleteAll` trên namespace secure storage dùng chung. Việc này xóa account authenticator local mà không có cảnh báo riêng.

Bắt buộc:

- tách namespace lưu session và account;
- quyết định sản phẩm rõ ràng về quyền sở hữu dữ liệu local;
- backup/export hoặc recovery behavior;
- regression test;
- warning text nếu vẫn chủ ý xóa.

### Log chứa secret

Luồng xử lý QR hiện in toàn bộ giá trị đã quét. URI `otpauth` hợp lệ chứa secret.

Bắt buộc:

- xóa log chứa credential;
- helper redaction tập trung;
- static review cho `secretKey`, `otpauth`, token, password, key, salt và recovery material;
- policy error reporting đã sanitize.

### Khả năng tái lập authorization

Có hướng dẫn RLS nhưng không có migration được track để chứng minh policy đã bật.

Bắt buộc:

- schema và policy được version control;
- test SELECT, INSERT, UPDATE và DELETE theo từng user;
- negative test cross-user;
- không có service-role credential trong client.

### Hành vi khi app lock lỗi

`LocalAuthError` chưa phải explicit deny condition của router. Khi lock đã được cấu hình, lỗi phải fail closed trừ khi có recovery policy được chủ ý thiết kế.

## Kịch bản đe dọa

| Kịch bản | Mức lộ hiện tại | Phản ứng bắt buộc |
|---|---|---|
| Supabase database bị lộ | TOTP secret đã sync đọc được | E2EE và migration plaintext |
| Backend operator ác ý hoặc nhầm lẫn | Secret đã sync đọc được | Ciphertext mà backend không thể đọc |
| Network gián đoạn khi upload | Cloud snapshot có thể bị xóa | Atomic commit và retry |
| Hai thiết bị sync đồng thời | Last writer có thể làm mất dữ liệu | Version/conflict protocol |
| Log thiết bị bị thu thập | QR secret có thể xuất hiện | Xóa và redact log |
| User logout trước khi sync | Account local bị xóa | Quyền sở hữu dữ liệu và cảnh báo an toàn |
| RLS thiếu hoặc sai | Có thể truy cập dữ liệu cross-user | Policy được track và negative test |
| Plugin local-auth lỗi | Có thể bypass lock | Routing fail-closed |

## Quy tắc secure coding

- Xem `secretKey` và URI `otpauth` là credential.
- Không dùng credential thật trong example, screenshot, issue, test fixture hoặc analytics.
- Không đưa service-role key vào Flutter hoặc static web build.
- Tránh log raw exception từ auth/storage khi có thể chứa identifier hoặc token.
- Validate algorithm, digits, period, label và Base32 input trước persistence.
- Dùng cryptographic operation từ library đã review; không tự viết primitive.
- Gắn version cho mọi encrypted format và remote persisted format.
- Giữ thao tác phá hủy có thể khôi phục và quan sát được.

## Security verification gate

Release production xử lý secret thật yêu cầu:

- threat model đã review;
- mọi blocker trên được xử lý hoặc owner chấp nhận rõ;
- unit test validation và serialization;
- storage recovery test;
- RLS integration test cross-user;
- test concurrency và interrupted sync;
- mobile lock lifecycle test;
- review dependency và platform security;
- privacy policy khớp hành vi production thật;
- quy trình xử lý incident và key compromise.

## Báo cáo

Không mở issue công khai có secret, token, email user hoặc production URL thật. Dùng kênh riêng do chủ dự án chọn và cung cấp reproduction step đã sanitize.
