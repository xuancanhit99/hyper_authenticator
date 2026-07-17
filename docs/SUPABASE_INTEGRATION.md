# Tích hợp Supabase

Tài liệu này mô tả client contract và self-hosted backend đã xác minh ngày
17 tháng 7 năm 2026. RLS đã triển khai nhưng remote payload vẫn chứa TOTP secret
plaintext, vì vậy backend chưa production-ready.

## Cấu hình client

`AppConfig` đọc compile-time environment:

- `SUPABASE_URL`;
- `SUPABASE_PUBLISHABLE_KEY`;
- `SUPABASE_ANON_KEY` chỉ là fallback tương thích cấu hình cũ.
- `PASSWORD_RECOVERY_URL` là public HTTPS URL canonical của recovery Web;
- `ALLOW_INSECURE_PLAINTEXT_SYNC` là bridge tạm cho migration/test ở non-release;
  mặc định `false` và luôn bị vô hiệu trong release build.

Development:

    cp .env.example .env
    flutter run --dart-define-from-file=.env

`.env` bị Git ignore và không được khai báo trong Flutter assets. Analyze/test/build
không cần configuration; runtime bootstrap cần URL và publishable key hợp lệ.

Quy tắc:

- Chỉ commit `.env.example` có placeholder.
- Không dùng service-role/secret key trong Flutter, static web hoặc CI client build.
- Publishable/anon key là public client configuration, không phải authorization
  boundary.
- Tách development, test, staging và production.
- Ghi allowed redirect URL và application identifier theo environment.
- Không đặt `ALLOW_INSECURE_PLAINTEXT_SYNC=true` trong file hoặc pipeline release.

`.env` local hiện đã được đồng bộ public URL/publishable key của instance mới và
giữ permission `0600`; giá trị không được đưa vào tài liệu hoặc Git.

## Authentication

Client đã có đăng ký email/password cùng name metadata, đăng nhập, auth-state
stream, gửi recovery email, cập nhật mật khẩu và đăng xuất. Local vault không yêu
cầu session; authentication chỉ cần cho cloud feature.

Deployment mới sinh cả legacy key đã rotate và opaque publishable/secret key. User
session JWT dùng ES256, JWKS chỉ công bố EC public key; test vẫn xác minh HS256
backward compatibility. Flutter chỉ dùng publishable key.

Logout không xóa TOTP local. Quyền sở hữu local data giữa nhiều Supabase user vẫn
cần product decision rõ ràng.

## Khôi phục mật khẩu

Web là canonical recovery surface theo ADR-0004. Flutter truyền
`PASSWORD_RECOVERY_URL` vào `resetPasswordForEmail`. `reset-password-web` đã nhận
public URL/key lúc container start, từ chối secret key,
không lưu session bền vững, không log recovery material, có CSP/security header và
pin dependency bằng version cùng SRI. Container chạy non-root, read-only và chỉ
bind loopback theo compose mẫu.

Image đóng gói `email-templates/recovery.html`; self-hosted Auth fetch template
qua `GOTRUE_MAILER_TEMPLATES_RECOVERY`. Template đặt one-time `token_hash` trong
fragment và Web gọi `verifyOtp`. Nó không thể
exchange `?code` PKCE được phát cho Flutter client vì code verifier nằm trong app.
Template/redirect allow-list chưa deploy và vẫn cần test link thành công, hết hạn,
reuse, malformed cùng cross-environment. SMTP config không chứng minh E2E hoạt động.

## Self-hosted baseline

Stack dùng release official được pin trong `supabase/UPSTREAM_PIN`:

- release `self-hosted/v0.7.0`, commit
  `244301c09ddba21aa963ebea09e712ce89b0401a`;
- PostgreSQL 17.6.1.136;
- Studio, Kong, Auth, PostgREST, Realtime, Storage, imgproxy, postgres-meta,
  Edge Runtime và Supavisor theo cùng release bundle;
- public traffic qua reverse proxy HTTPS; Kong và Supavisor bind loopback;
- asymmetric Auth/JWKS và opaque API keys đã bật;
- Logs/Analytics chưa bật do RAM headroom chưa được load-test; disk hiện còn khoảng
  24 GB sau host cleanup.

Self-hosting khiến operator chịu trách nhiệm update, security hardening, backup,
monitoring, SMTP, DNS/TLS và disaster recovery. Overlay không nhạy cảm cùng cách
apply migration/test nằm trong `supabase/README.md`.

## Database contract đã triển khai

Migration:
`supabase/migrations/20260717163000_create_synced_accounts.sql`.

Table `public.synced_accounts`:

| Column | Kiểu | Contract |
|---|---|---|
| `user_id` | `uuid` | FK `auth.users`, owner và một phần primary key |
| `account_id` | `uuid` | Stable account ID và một phần primary key |
| `issuer` | `text` | Bắt buộc, 1–255 ký tự |
| `account_name` | `text` | Bắt buộc, 1–512 ký tự |
| `secret_key` | `text` | TOTP secret plaintext, 16–512 ký tự |
| `algorithm` | `text` | `SHA1`, `SHA256` hoặc `SHA512` |
| `digits` | `smallint` | 6–8 |
| `period` | `integer` | 1–300 giây |
| `format_version` | `smallint` | Default và giới hạn ở `1` |
| `updated_at` | `timestamptz` | Default UTC `now()` khi insert |

Primary key là `(user_id, account_id)`. Index `(user_id, updated_at desc)` hỗ trợ
truy vấn owner và last upload.

`SupabaseAccountMapper` là boundary duy nhất giữa model local camelCase và row
snake_case:

- `id` ↔ `account_id`;
- `accountName` ↔ `account_name`;
- `secretKey` ↔ `secret_key`;
- `issuer`, `algorithm`, `digits`, `period` giữ nguyên;
- `user_id` được lấy từ session hiện tại;
- `format_version`, `updated_at` do database default.

Client build trước migration còn gửi camelCase và **không tương thích** schema mới.
Backend và Flutter source hiện tại phải rollout cùng nhau.

## Sync behavior hiện tại

Toàn bộ cloud sync plaintext bị khóa mặc định ở cả `SyncBloc` và remote data
source. Release build luôn khóa kể cả khi define opt-in bị truyền nhầm. Phần dưới
chỉ mô tả compatibility bridge khi chạy non-release với
`ALLOW_INSECURE_PLAINTEXT_SYNC=true` trong environment migration/test cô lập.

### Download

Client select row của user hiện tại, mapper snake_case về
`AuthenticatorAccount`, giữ stable `account_id` cùng đủ algorithm/digits/period.
Merge nhận dạng theo stable ID, cho phép hai record trùng label nếu ID khác nhau và
để local thắng khi cùng ID. Success chỉ emit sau khi local persistence hoàn tất.

### Upload

1. Xóa mọi row có `user_id` của user hiện tại.
2. Map account local sang row snake_case.
3. Chèn toàn bộ snapshot; database gán `format_version` và `updated_at`.

### Truy vấn trạng thái

- `hasRemoteData` select `account_id` và limit một row.
- Last-upload time lấy `updated_at` mới nhất.

Xóa-rồi-chèn chưa atomic/idempotent và chưa có revision/tombstone. RLS ngăn
cross-user access nhưng không ngăn mất snapshot khi request bị gián đoạn; vì vậy
bridge này không được dùng trong release.

## Grant và RLS đã triển khai

Migration bật cả `ENABLE ROW LEVEL SECURITY` và `FORCE ROW LEVEL SECURITY`, revoke
mọi quyền từ `public`, `anon`, `authenticated`, sau đó grant đúng SELECT/INSERT/
UPDATE/DELETE cho `authenticated`.

| Operation | `USING` | `WITH CHECK` |
|---|---|---|
| SELECT | `auth.uid() = user_id` | — |
| INSERT | — | `auth.uid() = user_id` |
| UPDATE | `auth.uid() = user_id` | `auth.uid() = user_id` |
| DELETE | `auth.uid() = user_id` | — |

Catalog đã xác minh role `authenticated` không có TRUNCATE/REFERENCES/TRIGGER.
Service role vẫn có quyền vận hành và tuyệt đối không được phân phối cho client.

`scripts/supabase/test_remote_contract.sh` tạo hai isolated user rồi xác minh:

- anonymous không có SELECT;
- User A CRUD được row của chính mình;
- User B không select/update/delete row của User A;
- User B không insert row giả owner User A;
- TOTP parameter round-trip đúng;
- row và test user được dọn sạch.

Kết quả hiện tại: 17 pass, 0 fail qua public HTTPS endpoint.

## Dữ liệu và backup

Instance mới là fresh database, không import data cũ. Sau test/cleanup, Auth user,
Auth audit, Storage bucket/object, Realtime message và `synced_accounts` đều 0.

Backup legacy, checksum, rehearsal, restore limitation và chiến lược import chọn
lọc nằm trong [runbook backup legacy](operations/SUPABASE_LEGACY_BACKUP.md). Backup
chứa credential và không nằm trong repository.

## Encrypted contract v2 đang staged

Migration `20260718190000_create_encrypted_vault_snapshots.sql` thêm table một
snapshot/user và RPC `publish_encrypted_vault_snapshot`:

- AES-256-GCM envelope, nonce/tag và wrapped DEK;
- server-incremented revision, expected-revision conflict và atomic row update;
- SELECT owner-only RLS; write chỉ qua authenticated RPC;
- additive rollout, chưa drop `synced_accounts`.

Local crypto/key-store và ephemeral PostgreSQL migration harness đã pass. Client
remote orchestration/onboarding và deployment chưa hoàn tất, nên release sync vẫn
khóa. Xem ADR-0005 và `E2EE_DESIGN.md`.

## Failure behavior

Khi guard chặn, UI nhận `SyncUnavailable`, preference cũ được xóa nếu người dùng
thử bật sync và không có network call nào được thực hiện. Protocol tương lai phải
phân biệt unauthenticated, authorization denied, validation, network, conflict,
schema mismatch, interrupted upload và unsupported encrypted format. Destructive
retry phải có idempotency trước.

## Checklist environment

Quản lý ngoài repository:

- public domain, reverse proxy, TLS và owner;
- allowed redirect URL;
- email verification/recovery template và SMTP;
- rate limit, abuse control và log retention;
- migration version cùng RLS test result;
- encrypted off-host backup và restore rehearsal;
- resource alert cho disk/RAM/swap;
- incident/rotation owner.
