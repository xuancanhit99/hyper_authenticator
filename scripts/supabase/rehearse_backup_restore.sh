#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:?Usage: rehearse_backup_restore.sh BACKUP_DIR}
DB_CONTAINER=${DB_CONTAINER:-supabase-db}
RESTORE_LOCK_FILE=${RESTORE_LOCK_FILE:-$(dirname "$BACKUP_DIR")/.backup.lock}

umask 077

command -v flock >/dev/null 2>&1
exec 9>"$RESTORE_LOCK_FILE"
if ! flock -n 9; then
  printf '%s\n' 'Backup hoặc restore drill khác đang chạy.' >&2
  exit 75
fi

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

session_guard_ready=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select
     to_regprocedure('private.is_current_auth_session_active()') is not null
     and exists (
       select 1 from pg_proc
       where oid = 'private.is_current_auth_session_active()'::regprocedure
         and prosecdef
     )
     and exists (
       select 1 from pg_policies
       where schemaname = 'public'
         and tablename = 'encrypted_vault_snapshots'
         and policyname = 'encrypted_vault_select_own'
         and position('is_current_auth_session_active' in qual) > 0
     )
     and position(
       'is_current_auth_session_active'
       in pg_get_functiondef(
         'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'::regprocedure
       )
     ) > 0
     and position(
       'session_revoked'
       in pg_get_functiondef(
         'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'::regprocedure
       )
     ) > 0")
[[ "$session_guard_ready" == t ]]

device_registry_ready=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select
     to_regclass('public.authenticator_device_sessions') is not null
     and (
       select relrowsecurity and relforcerowsecurity
       from pg_class
       where oid = 'public.authenticator_device_sessions'::regclass
     )
     and not has_table_privilege(
       'authenticated', 'public.authenticator_device_sessions', 'select'
     )
     and exists (
       select 1 from pg_proc
       where oid = 'public.register_current_authenticator_device(uuid,text,text)'::regprocedure
         and prosecdef
     )
     and exists (
       select 1 from pg_proc
       where oid = 'public.list_authenticator_device_sessions()'::regprocedure
         and prosecdef
     )
     and exists (
       select 1 from pg_proc
       where oid = 'public.revoke_authenticator_device_session(uuid)'::regprocedure
         and prosecdef
     )
     and position(
       'delete from auth.sessions'
       in lower(pg_get_functiondef(
         'public.revoke_authenticator_device_session(uuid)'::regprocedure
       ))
     ) > 0")
[[ "$device_registry_ready" == t ]]

data_probe=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select count(*) >= 0 from auth.users; select count(*) >= 0 from public.encrypted_vault_snapshots")
[[ $(printf '%s\n' "$data_probe" | grep -c '^t$') -eq 2 ]]

printf '%s\n' \
  'Supabase restore rehearsal pass: checksum, catalog, full restore, schema, force-RLS, active-session và device-registry guard.'
