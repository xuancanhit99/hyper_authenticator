# Supabase harness

Thư mục này version-control backend contract, proxy overlay và service templates.
Secret, URL thật, database volume và backup thật không được commit.

## Nội dung

- `UPSTREAM_PIN`: exact self-hosted upstream pin.
- `docker-compose.public-proxy.yml`: loopback/public proxy network boundary.
- `docker-compose.recovery-web.yml`: Recovery Web template URL injection.
- `migrations/`: lịch sử plaintext schema, encrypted snapshot/device RPC và
  terminal plaintext-retirement/publish-hardening migrations.
- `systemd/`: daily backup, scheduled restore drill và 5-minute health
  service/timer templates.
- `launchd/`: encrypted off-host pull LaunchAgent template.
- `nginx-proxy-manager/`: non-secret production overlay cho Auth timing observability.
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

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260719070000_create_authenticator_device_registry.sql

Device-wrap client-v2 và hai migration đã deploy production ngày 19-07-2026 sau
full gate, backup/off-host copy và restore checkpoint. Command canonical:

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260719150000_add_device_specific_vault_keys.sql

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260719170000_allow_recovery_device_key_replacement.sql

Hai terminal migration 22-07-2026 đã deploy production sau fresh full backup,
encrypted off-host copy và zero-row preflight cho `public.synced_accounts`:

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260722100000_harden_device_wrap_publish.sql

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260722110000_retire_plaintext_synced_accounts.sql

Migration retirement đặt `row_security=off`, lấy `ACCESS EXCLUSIVE` lock rồi abort
nguyên transaction bằng `plaintext_legacy_rows_present` nếu còn row; operator
thiếu `BYPASSRLS` fail closed và không xóa dữ liệu để ép rollout. Migration publish
giữ legacy RPC cho initial revision `1` nhưng từ chối expected revision `NULL`;
update bắt buộc v2 protocol `1` với exact-row `FOR UPDATE` và active device binding.

Test migration local:

    scripts/supabase/test_encrypted_vault_migration.sh
    scripts/supabase/test_plaintext_retirement_migration.sh

Test remote trong protected operator context:

    scripts/supabase/test_remote_contract.sh \
      /path/to/supabase/.env https://api.example.com

    scripts/supabase/test_remote_encrypted_vault_contract.sh \
      /path/to/supabase/.env https://api.example.com

    scripts/supabase/test_remote_recovery_contract.sh \
      /path/to/supabase/.env https://api.example.com \
      https://auth.example.com/reset-password/

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

`test_remote_contract.sh` không tạo user; nó xác minh cả public và service role đều
nhận table-absent sau plaintext retirement. Các suite còn lại cần service-role key
để tạo/dọn isolated user. Không copy key vào Flutter `.env`, CI fork hoặc shell
trace.

Encrypted remote suite hiện có 36 assertion cho expected-revision `NULL`, negative legacy cutoff, đăng ký
native device, enroll/self-wrap/confirm protocol `1`, publish revision `2` qua v2,
session revoke và cross-tenant isolation. Production ngày 22-07-2026 đã pass
36/36; nó vẫn phải chạy lại trên public HTTPS sau mỗi deploy/restore liên quan,
vì local contract không thay thế evidence này.

## Operations

- `backup_production.sh`: DB/globals/Storage/config + checksum/catalog/tar verify.
- `check_production_health.sh`: container/resource/RLS/public endpoint/backup age.
- `rehearse_backup_restore.sh`: full restore vào DB tạm, probe schema/FORCE RLS, drop.
- `run_scheduled_restore_drill.sh`: due/retry orchestration, shared backup lock và
  atomic 0600 evidence; health kiểm tra freshness qua `check_restore_drill_state.sh`.
- `pull_encrypted_backup.sh`: SSH stream → `age`, không tạo plaintext local archive.

Chi tiết deploy/service/retention/incident:
`../docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`.

## Trạng thái production đã xác minh

- 11 core container healthy.
- Encrypted remote contract 36/36, gồm null/legacy cutoff, device-bound v2, revoke session cũ và
  active-session RLS/RPC.
- Recovery contract 8/8.
- Studio HTTPS + Basic Auth proxy contract pass.
- Daily backup service, scheduled restore rehearsal và encrypted off-host
  LaunchAgent pass.
- Health/backup/restore-drill timers active.
- Post-P0 backup `supabase-20260722T155219Z` và corrective-review pre/post backup
  `supabase-20260722T161217Z`/`supabase-20260722T161534Z`, restore rehearsal cùng
  encrypted off-host copy đều pass; final app-data audit bằng 0, plaintext table
  absent và production legacy RPC có explicit `NULL` guard.

## Compatibility và rollback

Plaintext datasource/mapper/repository/use case đã bị xóa khỏi client; poison flag
`ALLOW_INSECURE_PLAINTEXT_SYNC=true` bị từ chối ở mọi build. Terminal migration chỉ
drop `synced_accounts.secret_key` khi table rỗng và đã có backup xác minh. Binary cũ
sẽ fail closed sau cutoff, không có compatibility write path.

Encrypted rollback giữ local vault/current encrypted row và tắt cloud capability
thay vì ghi plaintext. Sau khi table đã drop, rollback destructive phải restore
full backup cùng release/schema tương thích trong maintenance window; không tạo lại
table hoặc grant PostgREST thủ công.

## Khoảng trống

- External alert channel.
- Dedicated off-host backup system/PITR.
- SMTP mailbox delivery/expired-link E2E.
- Client chưa expose per-device cryptographic exclusion; targeted revoke chỉ thu
  hồi auth session.
