# ADR-0001: Pin Supabase self-hosted và version hóa remote contract

- Trạng thái: Chấp nhận
- Ngày: 2026-07-17
- Owner: Repository owner
- Thay thế: Deployment legacy không có versioned migration
- Bị thay thế một phần bởi: ADR-0005, ADR-0013

## Bối cảnh

Instance legacy dùng PostgreSQL 15 cùng một tập image rời rạc, không có migration
cho Hyper Authenticator, không có backup automation và thiếu một số component
trong Docker bundle official hiện tại. Flutter client cũ gửi key camelCase trong
khi PostgreSQL convention và contract mới cần snake_case. TOTP secret vẫn đang ở
plaintext nên backend này chưa đủ điều kiện production.

## Quyết định

- Dùng Docker bundle official theo release, pin cả tag và commit trong
  `supabase/UPSTREAM_PIN`; không deploy trực tiếp từ nhánh `master`.
- Baseline hiện tại là `self-hosted/v0.7.0`, PostgreSQL 17 và toàn bộ core service
  của bundle. Logs/Analytics không bật cho tới khi host đủ resource.
- Chỉ công bố API qua reverse proxy HTTPS. Kong, Supavisor session và transaction
  port bind loopback; Kong tham gia external Docker network của reverse proxy.
- Version hóa schema `public.synced_accounts` bằng migration. Client map model
  camelCase sang row snake_case tại data boundary.
- Bật và force RLS; chỉ role `authenticated` có CRUD, với policy
  `auth.uid() = user_id` cho từng operation.
- Xem schema plaintext này là compatibility bridge. E2EE và atomic sync phải có
  ADR khác trước production.

## Phương án đã cân nhắc

### Giữ nguyên stack legacy và sửa tại chỗ

Ít thay đổi tức thời nhưng giữ PostgreSQL/image cũ, cấu hình drift và schema không
tái lập. Không chọn vì instance cần clean toàn bộ data và có backup legacy riêng.

### Theo dõi nhánh Supabase `master`

Có thay đổi mới nhất nhưng bao gồm phần `Unreleased`, khó rollback và không có
release provenance ổn định. Không chọn.

### Dùng Supabase hosted

Giảm trách nhiệm vận hành nhưng thay đổi deployment ownership hiện tại. Không nằm
trong phạm vi của đợt làm mới self-hosted này.

## Hệ quả

### Tích cực

- Stack, schema và security boundary có thể tái lập.
- Flutter giữ model nội bộ hiện tại nhưng PostgreSQL contract nhất quán.
- Có smoke test official, asymmetric-key test và cross-user RLS contract test.

### Tiêu cực

- Client build cũ gửi camelCase không tương thích với schema mới.
- Operator vẫn chịu trách nhiệm update, backup, monitoring, SMTP, TLS và incident.
- Logs/Analytics chưa có trên host resource-constrained.

### Rủi ro

- Plaintext TOTP secret có thể bị backend operator hoặc database compromise đọc.
- Xóa-rồi-chèn có thể mất snapshot khi upload gián đoạn.
- Reverse proxy phụ thuộc external network `proxy-network`; mất network attachment
  sẽ gây `502` dù core container vẫn healthy.

## Bảo mật và quyền riêng tư

Service-role/secret key chỉ tồn tại ở server operator environment. Flutter chỉ
nhận publishable key. RLS là authorization boundary nhưng không phải encryption.
Backup legacy chứa password hash, token lịch sử và provider key nên phải giữ mode
`0700/0600`, mã hóa khi sao chép và không đưa vào source control.

## Dữ liệu và compatibility

Migration mới chỉ dành cho fresh database. Dữ liệu legacy không được import.
Remote row dùng `user_id`, `account_id`, `issuer`, `account_name`, `secret_key`,
`algorithm`, `digits`, `period`, `format_version`, `updated_at`. Client hiện tại
map đủ tham số TOTP; `format_version` và `updated_at` dùng database default.

Rollback backend cần dùng backup legacy với đúng image inventory trong environment
cô lập. Rollback client sang bản camelCase không được thực hiện trên schema mới.

## Xác minh

- `tests/test-self-hosted.sh`: 35 pass, 0 fail qua public HTTPS endpoint.
- `tests/test-auth-keys.sh`: 43 pass, 0 fail; user JWT dùng ES256.
- `scripts/supabase/test_remote_contract.sh`: 17 pass, 0 fail.
- Catalog xác nhận force RLS, bốn policy owner-only và grant CRUD tối thiểu.
- Unit test mapper xác nhận snake_case và TOTP parameter round-trip.

## Rollout

1. Backup/checksum/rehearsal legacy trước khi xóa.
2. Dựng fresh stack từ release pin, rotate mọi secret và kết nối reverse proxy.
3. Áp dụng migration rồi chạy toàn bộ test qua public endpoint.
4. Dọn test data, cập nhật public client config và build Flutter từ cùng commit.
5. Rollback nếu service unhealthy, public TLS path lỗi hoặc RLS negative test fail.

## Ghi chú thay thế — 22-07-2026

ADR này vẫn là nguồn quyết định cho việc pin Supabase self-hosted, version hóa
migration, public HTTPS và RLS. Các đoạn mô tả `public.synced_accounts`, mapper
snake_case và plaintext compatibility bridge ở trên là trạng thái lịch sử tại
thời điểm chấp nhận:

- [ADR-0005](0005-e2ee-versioned-snapshot-sync.md) thay đường sync runtime bằng
  encrypted versioned snapshot với recovery key do người dùng giữ.
- [ADR-0013](0013-retire-plaintext-and-require-device-bound-publish.md) xóa client
  plaintext path, drop bảng chỉ khi zero-row preflight pass và khóa update sau
  revision đầu tiên vào device-bound publish.

Không dùng phần schema plaintext lịch sử của ADR này làm contract runtime hiện
tại. Bằng chứng deploy mới nhất nằm trong `docs/PROJECT_STATUS.md`.
