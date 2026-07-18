# Supabase harness

Thư mục này giữ phần có thể version control của backend contract. Secret, public URL,
database volume và backup không được đặt trong repository.

## Nội dung

- `UPSTREAM_PIN`: release/commit official đã dùng để dựng stack hiện tại.
- `docker-compose.public-proxy.yml`: overlay bind Kong/Supavisor vào loopback,
  đồng thời nối Kong và Studio vào external network `proxy-network` để reverse
  proxy resolve upstream bằng service name.
- `docker-compose.recovery-web.yml`: inject internal recovery-template URL vào
  Auth; URL thật nằm trong `.env` operator, không nằm trong repository.
- `migrations/`: schema, grant và RLS policy của ứng dụng.
- `../scripts/supabase/test_remote_contract.sh`: isolated end-to-end test cho
  Auth, mapper contract và cross-user RLS.
- `../scripts/supabase/test_encrypted_vault_migration.sh`: PostgreSQL ephemeral
  test cho encrypted snapshot revision/conflict/RLS, không cần remote secret.
- `../scripts/supabase/test_remote_encrypted_vault_contract.sh`: PostgREST/Auth
  contract cho encrypted snapshot trên isolated self-hosted environment.
- `../scripts/supabase/test_remote_recovery_contract.sh`: one-time recovery-token,
  password update/re-login/reuse contract; không gửi email thật.
- `../scripts/supabase/test_remote_studio_proxy.sh`: health/network/DNS/upstream
  contract cho Studio và Basic Auth public boundary.

## Áp dụng trên một stack mới

1. Checkout đúng release/commit trong `UPSTREAM_PIN` từ repository Supabase.
2. Sinh secret/key mới bằng utility official; không sao chép `.env` production
   vào repository hoặc client build.
3. Copy overlay thành `docker-compose.local.yml` cạnh compose official và xác
   minh external network `proxy-network` đã tồn tại.
4. Start stack, chờ toàn bộ core service healthy rồi áp dụng migration theo thứ
   tự tên file.
5. Chạy smoke test official, auth-key test official và contract test của dự án.
6. Dọn isolated test user/data và xác nhận các table ứng dụng rỗng trước bàn giao.

Ví dụ áp dụng migration từ host chạy Docker:

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260717163000_create_synced_accounts.sql

Ví dụ chạy RLS contract test ngay trên server, nơi `.env` của stack được bảo vệ:

    scripts/supabase/test_remote_contract.sh /path/to/supabase/.env

Trước khi deploy E2EE migration additive:

    scripts/supabase/test_encrypted_vault_migration.sh

Sau đó áp migration `20260718190000_create_encrypted_vault_snapshots.sql` trên
staging trước. Migration không drop/sửa table plaintext. Baseline self-hosted hiện
tại đã deploy migration này và pass 11 remote contract check; xem
`docs/operations/SUPABASE_E2EE_ROLLOUT.md`.

Script cần `SERVICE_ROLE_KEY` để tạo và dọn isolated user. Không copy key này
vào `.env` của Flutter; không chạy script trong log có shell tracing.

Khi deploy Recovery Web, thêm exact URL vào `ADDITIONAL_REDIRECT_URLS`, đặt
`GOTRUE_MAILER_TEMPLATES_RECOVERY` trong server `.env`, rồi recreate riêng Auth:

    docker compose -f compose.yaml -f compose.recovery-web.yml up -d --no-deps auth

Remote recovery contract không gửi email thật và dọn user bằng Admin API. GoTrue
vẫn giữ audit entry; chỉ xóa audit trong isolated zero-data rehearsal, không xóa
audit production.

Sau khi recreate Studio hoặc Docker network, chạy trên server:

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

Public status `401` khi không có credential là expected vì dashboard dùng Basic
Auth. Contract còn xác minh Nginx Proxy Manager resolve được `supabase-studio` và
upstream profile trả 200; container healthy một mình không đủ chứng minh route.

## Giới hạn hiện tại

`synced_accounts.secret_key` vẫn là plaintext compatibility table và upload cũ vẫn
xóa-rồi-chèn. Encrypted schema/RPC v2 đã deploy nhưng chưa nối client; release sync
vẫn khóa. Backup định kỳ và restore rehearsal vẫn bắt buộc.
