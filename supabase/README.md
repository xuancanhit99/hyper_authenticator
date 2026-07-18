# Supabase harness

Thư mục này version-control backend contract, proxy overlay và service templates.
Secret, URL thật, database volume và backup thật không được commit.

## Nội dung

- `UPSTREAM_PIN`: exact self-hosted upstream pin.
- `docker-compose.public-proxy.yml`: loopback/public proxy network boundary.
- `docker-compose.recovery-web.yml`: Recovery Web template URL injection.
- `migrations/`: plaintext compatibility và encrypted snapshot/RPC schema.
- `systemd/`: daily backup và 5-minute health service/timer templates.
- `launchd/`: encrypted off-host pull LaunchAgent template.
- `../scripts/supabase/`: migration, remote contract, backup, health và restore harness.

## Dựng stack mới

1. Checkout exact official self-hosted pin trong `UPSTREAM_PIN`.
2. Sinh toàn bộ secret/key mới bằng official utility; không copy production env vào repo.
3. Cấu hình reverse proxy network và loopback binding.
4. Start stack; chờ 11 core container healthy.
5. Apply migration theo thứ tự filename.
6. Deploy Recovery Web + exact redirect allow-list/template.
7. Chạy encrypted/recovery/Studio contract.
8. Xác nhận isolated test user/data đã cleanup.
9. Cài backup/health timer và chạy restore rehearsal trước nhận traffic.

Apply E2EE migration:

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260718190000_create_encrypted_vault_snapshots.sql

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260718230000_enforce_active_vault_sessions.sql

Test migration local:

    scripts/supabase/test_encrypted_vault_migration.sh

Test remote trong protected operator context:

    scripts/supabase/test_remote_encrypted_vault_contract.sh \
      /path/to/supabase/.env https://api.example.com

    scripts/supabase/test_remote_recovery_contract.sh \
      /path/to/supabase/.env https://api.example.com \
      https://auth.example.com/reset-password/

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

Các script cần service-role key để tạo/dọn isolated user. Không copy key vào Flutter
`.env`, CI fork hoặc shell trace.

## Operations

- `backup_production.sh`: DB/globals/Storage/config + checksum/catalog/tar verify.
- `check_production_health.sh`: container/resource/RLS/public endpoint/backup age.
- `rehearse_backup_restore.sh`: full restore vào DB tạm, probe schema/FORCE RLS, drop.
- `pull_encrypted_backup.sh`: SSH stream → `age`, không tạo plaintext local archive.

Chi tiết deploy/service/retention/incident:
`../docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`.

## Trạng thái production đã xác minh

- 11 core container healthy.
- Encrypted remote contract 20/20, gồm revoke session cũ và active-session RLS/RPC.
- Recovery contract 8/8.
- Studio HTTPS + Basic Auth proxy contract pass.
- Daily backup service, restore rehearsal và encrypted off-host LaunchAgent pass.
- Health/backup timers active.
- Restore rehearsal xác minh FORCE RLS và active-session guard.

## Compatibility và rollback

`synced_accounts.secret_key` là plaintext compatibility table. Runtime client mới
không inject bridge và release guard chặn nó. Không drop table trong client rollout;
drop chỉ qua migration riêng sau backup/migration audit.

Encrypted rollback giữ local vault và current encrypted row; tắt cloud capability
thay vì ghi plaintext.

## Khoảng trống

- External alert channel.
- Dedicated off-host backup system/PITR.
- SMTP mailbox delivery/expired-link E2E.
