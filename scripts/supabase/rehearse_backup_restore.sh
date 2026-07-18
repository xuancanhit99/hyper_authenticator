#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:?Usage: rehearse_backup_restore.sh BACKUP_DIR}
DB_CONTAINER=${DB_CONTAINER:-supabase-db}

[[ -d "$BACKUP_DIR" ]]
[[ -f "$BACKUP_DIR/database-full.dump" ]]
[[ -f "$BACKUP_DIR/SHA256SUMS" ]]

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS >/dev/null
)
docker exec -i "$DB_CONTAINER" pg_restore --list \
  <"$BACKUP_DIR/database-full.dump" >/dev/null

database_name="ha_restore_rehearsal_$(date -u +%Y%m%d%H%M%S)_$RANDOM"
cleanup() {
  docker exec "$DB_CONTAINER" dropdb \
    -U supabase_admin --if-exists --force "$database_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker exec "$DB_CONTAINER" createdb -U supabase_admin "$database_name"
docker exec -i "$DB_CONTAINER" pg_restore \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  -U supabase_admin \
  -d "$database_name" <"$BACKUP_DIR/database-full.dump"

schema_ready=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select to_regclass('auth.users') is not null and to_regclass('public.encrypted_vault_snapshots') is not null")
[[ "$schema_ready" == t ]]

rls_ready=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.encrypted_vault_snapshots'::regclass")
[[ "$rls_ready" == t ]]

data_probe=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select count(*) >= 0 from auth.users; select count(*) >= 0 from public.encrypted_vault_snapshots")
[[ $(printf '%s\n' "$data_probe" | grep -c '^t$') -eq 2 ]]

printf '%s\n' \
  'Supabase restore rehearsal pass: checksum, catalog, full restore, schema và force-RLS.'
