# Mô hình bảo mật

## Trạng thái

Dự án là alpha. Local record dùng versioned secure-storage snapshot và remote
table có force RLS đã test. Cloud sync plaintext hiện bị khóa mặc định, nhưng
protocol chưa có E2EE/atomic publication nên chưa đủ an toàn cho production.

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
- Supabase Auth/JWKS với PostgreSQL force RLS đã deploy.
- Reverse proxy HTTPS với Kong/Supavisor bind loopback trên host self-hosted.
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
- `synced_accounts` có grant CRUD tối thiểu, force RLS và bốn owner-only policy.
- Cross-user RLS contract test pass cho anonymous cùng SELECT/INSERT/UPDATE/DELETE.
- User session JWT dùng ES256; JWKS không công bố symmetric key. Legacy HS256 chỉ
  được giữ cho backward verification trong transition.
- Public API đi qua reverse proxy TLS; database, Kong và Supavisor không mở trực
  tiếp ra mọi interface.
- Plaintext cloud sync fail closed nếu build không truyền explicit dangerous flag.
- Local vault v2 publish commit marker sau record/manifest, fallback generation
  trước và không xóa legacy data trong migration.
- Recovery web chạy read-only/non-root, tắt access log, dùng CSP/no-store và không
  log recovery session/user/raw backend error.
- Android release build dừng nếu thiếu signing thay vì fallback debug.
- Local vault hoạt động không cần Supabase session; app lock vẫn fail closed và
  logout không vô hiệu hóa lock.
- E2EE primitive dùng AES-256-GCM, AAD bind user/revision, random DEK cùng random
  recovery key; tamper/wrong-user/wrong-key regression test đều fail.

Các control này không biến plaintext cloud sync thành E2EE.

## Release blocker

### Đồng bộ plaintext

`AuthenticatorAccount.toJson` chứa `secretKey`; dangerous migration/test flag có
thể cho compatibility sync map trực tiếp vào Supabase. Production phải giữ
`ALLOW_INSECURE_PLAINTEXT_SYNC=false`.

AES-256-GCM envelope, key wrapping, secure key store và additive schema/RPC v2 đã
có. Còn thiếu onboarding/export/import recovery key, client remote orchestration,
staging rollout và plaintext migration trước khi có thể bật sync release.

### Upload phá hủy, không atomic

Upload xóa mọi row rồi chèn snapshot. Lỗi sau delete có thể làm mất cloud copy. Cần transaction/versioned snapshot, optimistic concurrency, idempotent retry và interrupted-write recovery.

### Authorization và operator boundary

Migration/RLS cùng cross-user test đã có, nhưng self-hosted operator và service
role vẫn có thể đọc plaintext. RLS không bảo vệ trước database dump, backend
compromise hoặc credential vận hành bị lộ. Cần secret rotation, encrypted backup,
least-privilege operator access, monitoring và định kỳ chạy lại negative test.

### Identity và ownership

- Merge đã dùng stable ID và giữ local khi trùng ID, nhưng chưa xử lý revision,
  secret rotation conflict, deletion hoặc concurrent device.
- TOTP local thuộc installation/profile local và được chia sẻ giữa các Supabase
  session trên cùng OS profile sau khi app unlock; đây là policy đã chấp nhận.
- Local storage có versioned commit/recovery nhưng chưa compaction và chưa có device integration evidence.

### Platform và recovery

- Web secure storage không có cùng threat model với Keychain/Keystore.
- Recovery web đã harden nhưng email template/token-hash redirect và E2E chưa rollout.
- Release signing, entitlement, installer và device verification chưa đủ.

### Backup và vận hành self-hosted

Backup legacy chứa password hash, token lịch sử và provider credential; file được
giữ ngoài repository với mode `0700/0600`. Chưa có encrypted off-host copy, lịch
backup định kỳ hoặc automated restore rehearsal cho instance mới. Disk headroom đã
được khôi phục; RAM headroom cho Logs/Analytics vẫn chưa được load-test an toàn.
SSH password và keyboard-interactive authentication đã tắt; server chỉ chấp nhận
public key. Fail2ban/UFW chưa cấu hình nên connection-rate protection vẫn là
defense-in-depth follow-up.

## Kịch bản đe dọa

| Kịch bản | Mức lộ hiện tại | Phản ứng bắt buộc |
|---|---|---|
| Supabase DB/backend operator bị lộ | Đọc bridge plaintext; v2 chỉ lộ ciphertext/metadata | Hoàn tất E2EE rollout và migration plaintext |
| Mất recovery key và mọi trusted device | Không thể giải mã cloud vault | One-time export confirmation và recovery rehearsal |
| Network gián đoạn khi upload | Có thể mất cloud snapshot | Atomic commit và idempotent retry |
| Hai thiết bị sync đồng thời | Last writer làm mất dữ liệu | Revision/conflict protocol |
| RLS regression sau migration/update | Cross-user access | Catalog audit và negative test mỗi rollout |
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
