# Supabase backend contract

## Canonical migration

- `migrations/20260802000000_create_minimal_encrypted_vault.sql`: production
  history hiện tại, bị ADR-0020 thay thế.
- `migrations/20260804000000_create_account_managed_sync.sql`: breaking
  account-managed sync migration đã deploy.
- `migrations/20260805000000_add_account_sync_realtime_signal.sql`: additive
  private Broadcast wake-up; không đổi account/Vault payload.
- `migrations/20260805010000_fix_account_sync_realtime_authorization.sql`:
  corrective policy cho authorization probe của Realtime 2.102.3.

Migration mới drop Minimal E2EE snapshot/RPC, tạo Vault-backed per-account table,
authenticated RPC, CAS và tombstone. Không dual-write/fallback.

Migration Realtime tạo own-user private topic policy và credential-free trigger.
Không cấp direct table `SELECT`, không cấp client Broadcast `INSERT` và không bật
Postgres Changes cho account table.

## Local test

```bash
scripts/supabase/test_account_sync_migration.sh
```

Harness pin đúng Supabase Postgres image production và kiểm tra Vault ciphertext,
ACL/RLS/RPC, tenant isolation, payload bounds, CAS, tombstone và cleanup object cũ.

## Production apply

Chỉ apply sau full backup/off-host copy/restore rehearsal:

```bash
docker exec -i supabase-db \
  psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  < supabase/migrations/20260804000000_create_account_managed_sync.sql

docker exec -i supabase-db \
  psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  < supabase/migrations/20260805000000_add_account_sync_realtime_signal.sql

docker exec -i supabase-db \
  psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  < supabase/migrations/20260805010000_fix_account_sync_realtime_authorization.sql
```

Sau deploy:

```bash
scripts/supabase/check_production_health.sh
scripts/supabase/test_remote_account_sync_contract.sh \
  /secure/operator.env https://supabase.example.com
```

Operator env phải mode 0600, ngoài repository. Service-role key chỉ dùng để tạo/
xóa isolated test user, không đi vào Flutter process hoặc log.

## Backup/restore

- Pre-migration backup dùng `RESTORE_SCHEMA_MODE=minimal`.
- Post-migration backup dùng default `account-sync`.
- Manual restore/move project phải giữ đúng Supabase Vault root key cùng backup;
  ciphertext không hữu dụng nếu mất key.
- Health timer kiểm tra schema/ACL/Vault extension cùng backup/restore freshness.

Runbook canonical:
[SUPABASE_PRODUCTION_OPERATIONS.md](../docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md).

## Invariant

- Không service-role/DB/Vault/SSH secret trong client/Git.
- Không log RPC payload/TOTP secret.
- Table không direct client CRUD; chỉ RPC bind `auth.uid()`.
- Xóa dùng tombstone; stale client không revive.
- Local TOTP không bị server migration xóa.
