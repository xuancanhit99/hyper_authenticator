# Supabase harness

Thư mục này giữ phần có thể version control của backend contract. Secret, public URL,
database volume và backup không được đặt trong repository.

## Nội dung

- `UPSTREAM_PIN`: release/commit official đã dùng để dựng stack hiện tại.
- `docker-compose.public-proxy.yml`: overlay chỉ bind Kong/Supavisor vào
  loopback và nối Kong vào external network `proxy-network`.
- `migrations/`: schema, grant và RLS policy của ứng dụng.
- `../scripts/supabase/test_remote_contract.sh`: isolated end-to-end test cho
  Auth, mapper contract và cross-user RLS.
- `../scripts/supabase/test_encrypted_vault_migration.sh`: PostgreSQL ephemeral
  test cho encrypted snapshot revision/conflict/RLS, không cần remote secret.

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
staging trước. Migration không drop/sửa table plaintext.

Script cần `SERVICE_ROLE_KEY` để tạo và dọn isolated user. Không copy key này
vào `.env` của Flutter; không chạy script trong log có shell tracing.

## Giới hạn hiện tại

`synced_accounts.secret_key` vẫn là plaintext compatibility table và upload cũ vẫn
xóa-rồi-chèn. Encrypted schema/RPC v2 đã có trong source nhưng chưa deploy/nối client;
release sync vẫn khóa. Backup định kỳ và restore rehearsal vẫn bắt buộc.
