# Mô hình bảo mật

## Trạng thái

Dự án là alpha. Local record dùng secure-storage abstraction, nhưng cloud sync vẫn upload TOTP secret ở dạng plaintext và chưa đủ an toàn cho production.

## Asset cần bảo vệ

| Asset | Tác động khi bị lộ |
|---|---|
| TOTP `secretKey` / URI `otpauth` | Có thể tạo yếu tố xác thực thứ hai |
| Supabase session | Truy cập hoặc sửa cloud data của user |
| Email, tên và nhãn account | Privacy/phishing |
| Encryption key/recovery code tương lai | Giải mã hoặc khôi phục cloud secret |

## Trust boundary

- Flutter process với secure storage, SharedPreferences và local authentication.
- Flutter process với Supabase qua network.
- Supabase Auth với PostgreSQL RLS.
- Browser recovery page với Supabase.
- Build environment với public client configuration.

Client-side filter `user_id` không phải authorization boundary; RLS đã deploy mới là boundary.

## Control đã triển khai

- TOTP JSON lưu qua FlutterSecureStorage.
- App lock ủy quyền biometrics/device credential cho OS và fail closed khi đã bật nhưng plugin lỗi.
- App relock khi rời foreground.
- QR input được validate tập trung và không log raw URI/secret.
- Logout giữ TOTP local; không gọi `deleteAll` trên shared secure storage.
- Supabase client chỉ nhận publishable/anon key; không cần service-role key.
- `.env` bị Git ignore, không đóng gói asset.
- Production path không còn log email, token hoặc TOTP secret đã biết.

Các control này không biến plaintext cloud sync thành E2EE.

## Release blocker

### Đồng bộ plaintext

`AuthenticatorAccount.toJson` chứa `secretKey`; sync map này trực tiếp vào Supabase. Chưa có encryption, authentication tag, key derivation/wrapping hoặc versioned envelope.

Cần E2EE ADR, authenticated encryption có version, bootstrap/recovery key đa thiết bị, migration plaintext và cryptographic/integration test.

### Upload phá hủy, không atomic

Upload xóa mọi row rồi chèn snapshot. Lỗi sau delete có thể làm mất cloud copy. Cần transaction/versioned snapshot, optimistic concurrency, idempotent retry và interrupted-write recovery.

### Authorization chưa tái lập

Repository chưa track migration/schema/RLS policy. Cần version control và negative test cho SELECT/INSERT/UPDATE/DELETE giữa nhiều user.

### Identity và ownership

- Merge không xử lý secret rotation, conflict, deletion hoặc concurrent device.
- TOTP local được giữ khi logout, nhưng policy chia sẻ/tách dữ liệu giữa nhiều Supabase user trên cùng thiết bị chưa được quyết định.
- Local secure-storage record và index chưa transactional.

### Platform và recovery

- Web secure storage không có cùng threat model với Keychain/Keystore.
- Password recovery deep link/static page chưa hoàn thiện.
- Release signing, entitlement, installer và device verification chưa đủ.

## Kịch bản đe dọa

| Kịch bản | Mức lộ hiện tại | Phản ứng bắt buộc |
|---|---|---|
| Supabase DB/backend operator bị lộ | Đọc được secret đã sync | E2EE và migration plaintext |
| Network gián đoạn khi upload | Có thể mất cloud snapshot | Atomic commit và idempotent retry |
| Hai thiết bị sync đồng thời | Last writer làm mất dữ liệu | Revision/conflict protocol |
| RLS thiếu/sai | Cross-user access | Migration và negative test |
| Secure storage index hỏng | Record orphan/mất tham chiếu | Recovery protocol |
| Browser/XSS trên Web | Có thể tác động local data/session | Web threat model, CSP và giới hạn cam kết |

Các regression đã xử lý: log QR secret, xóa TOTP khi logout, bypass lock do local-auth error và tiếp tục upload sau merge failure.

## Quy tắc secure coding

- Xem `secretKey`, URI `otpauth`, token, password và recovery material là credential.
- Không dùng credential thật trong example, test, screenshot, issue hoặc analytics.
- Không đưa server secret vào Flutter/static Web.
- Validate Base32, algorithm, digits, period và label trước persistence.
- Dùng cryptographic library đã review; không tự viết primitive.
- Gắn version cho encrypted/persisted format.
- Destructive operation phải quan sát được, idempotent và có recovery.
- Sanitize exception trước logging/telemetry.

## Security release gate

Production xử lý secret thật yêu cầu:

- threat model và E2EE design được review;
- plaintext sync blocker được loại bỏ;
- RLS migration và cross-user test pass;
- interrupted sync/concurrency/recovery test pass;
- mobile lock lifecycle và storage test pass;
- dependency/platform security review;
- privacy policy, incident và key-compromise procedure hoàn chỉnh.

## Báo cáo

Không mở issue công khai chứa secret, token, email user hoặc production URL. Dùng kênh riêng do owner chỉ định và reproduction đã sanitize.
