#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:?Usage: rehearse_backup_restore.sh BACKUP_DIR}
DB_CONTAINER=${DB_CONTAINER:-supabase-db}
RESTORE_LOCK_FILE=${RESTORE_LOCK_FILE:-$(dirname "$BACKUP_DIR")/.backup.lock}
RESTORE_SCHEMA_MODE=${RESTORE_SCHEMA_MODE:-account-sync}

case "$RESTORE_SCHEMA_MODE" in
  account-sync | account-sync-pre-realtime | minimal | pre-minimal) ;;
  *)
    printf 'RESTORE_SCHEMA_MODE không hợp lệ: %s\n' "$RESTORE_SCHEMA_MODE" >&2
    exit 64
    ;;
esac

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
  -U supabase_admin \
  -d "$database_name" <"$BACKUP_DIR/database-full.dump"

if [[ "$RESTORE_SCHEMA_MODE" == account-sync ||
  "$RESTORE_SCHEMA_MODE" == account-sync-pre-realtime ]]; then
  contract_ready=$(docker exec "$DB_CONTAINER" psql \
    -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
    "select
       to_regclass('auth.users') is not null
       and to_regclass('public.authenticator_accounts') is not null
       and (select relrowsecurity and relforcerowsecurity from pg_class
         where oid = 'public.authenticator_accounts'::regclass)
       and not has_table_privilege(
         'authenticated', 'public.authenticator_accounts',
         'select,insert,update,delete'
       )
       and has_function_privilege(
         'authenticated', 'public.list_authenticator_accounts()', 'execute'
       )
       and has_function_privilege(
         'authenticated',
         'public.upsert_authenticator_account(uuid,bigint,jsonb)', 'execute'
       )
       and has_function_privilege(
         'authenticated',
         'public.delete_authenticator_account(uuid,bigint)', 'execute'
       )
       and exists (select 1 from pg_extension where extname = 'supabase_vault')
       and to_regclass('public.encrypted_vault_snapshots') is null
       and to_regclass('public.synced_accounts') is null
       and to_regprocedure(
         'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'
       ) is null")
  data_table=public.authenticator_accounts
  if [[ "$RESTORE_SCHEMA_MODE" == account-sync ]]; then
    realtime_ready=$(docker exec "$DB_CONTAINER" psql \
      -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
      "select
         (select prosecdef from pg_proc where oid =
           'private.broadcast_account_sync_change()'::regprocedure)
         and exists (
           select 1 from pg_trigger
           where tgrelid = 'public.authenticator_accounts'::regclass
             and tgname = 'broadcast_account_sync_change'
             and not tgisinternal
         )
         and exists (
           select 1 from pg_policy
           where polrelid = 'realtime.messages'::regclass
             and polname = 'account_sync_receive_own_broadcast'
             and polcmd = 'r'
         )
         and (
           select pg_get_expr(polqual, polrelid) not ilike '%private%'
           from pg_policy
           where polrelid = 'realtime.messages'::regclass
             and polname = 'account_sync_receive_own_broadcast'
         )
         and not exists (
           select 1 from pg_publication_tables
           where schemaname = 'public'
             and tablename = 'authenticator_accounts'
         )")
  else
    realtime_ready=$(docker exec "$DB_CONTAINER" psql \
      -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
      "select
         to_regprocedure('private.broadcast_account_sync_change()') is null
         and not exists (
           select 1 from pg_policy
           where polrelid = 'realtime.messages'::regclass
             and polname = 'account_sync_receive_own_broadcast'
         )")
  fi
  [[ "$realtime_ready" == t ]]
elif [[ "$RESTORE_SCHEMA_MODE" == minimal ]]; then
  contract_ready=$(docker exec "$DB_CONTAINER" psql \
    -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
    "select to_regclass('auth.users') is not null
       and to_regclass('public.encrypted_vault_snapshots') is not null
       and (select relrowsecurity and relforcerowsecurity from pg_class
         where oid = 'public.encrypted_vault_snapshots'::regclass)
       and to_regprocedure(
         'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'
       ) is not null")
  data_table=public.encrypted_vault_snapshots
else
  # Backup ngay trước ADR-0019 phải restore được nguyên legacy encrypted
  # protocol để rollback production. Mode này chỉ verify backup; không làm các
  # object cũ trở thành contract được phép cho deployment mới.
  contract_ready=$(docker exec "$DB_CONTAINER" psql \
    -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
    "select
       to_regclass('public.authenticator_device_sessions') is not null
       and to_regclass('public.authenticator_device_keys') is not null
       and to_regclass('public.authenticator_device_key_wraps') is not null
       and exists (
         select 1 from pg_proc
         where pronamespace = 'public'::regnamespace
           and proname = 'publish_encrypted_vault_snapshot_v2'
           and prosecdef
       )")
  data_table=public.encrypted_vault_snapshots
fi
[[ "$contract_ready" == t ]]

data_probe=$(docker exec "$DB_CONTAINER" psql \
  -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" -Atqc \
  "select count(*) >= 0 from auth.users; select count(*) >= 0 from $data_table")
[[ $(printf '%s\n' "$data_probe" | grep -c '^t$') -eq 2 ]]

printf '%s\n' \
  "Supabase restore rehearsal pass: checksum, catalog, full restore và $RESTORE_SCHEMA_MODE contract."
