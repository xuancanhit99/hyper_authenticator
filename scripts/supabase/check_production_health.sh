#!/usr/bin/env bash
set -euo pipefail

STACK_ENV=${STACK_ENV:-/opt/stacks/supabase/.env}
BACKUP_ROOT=${BACKUP_ROOT:-/home/xuancanhit/backups/hyper-authenticator/scheduled}
API_ORIGIN=${API_ORIGIN:-}
RECOVERY_ORIGIN=${RECOVERY_ORIGIN:-}
MAX_DISK_PERCENT=${MAX_DISK_PERCENT:-85}
MIN_AVAILABLE_MEMORY_KIB=${MIN_AVAILABLE_MEMORY_KIB:-1048576}
MAX_BACKUP_AGE_SECONDS=${MAX_BACKUP_AGE_SECONDS:-108000}
RESTORE_DRILL_STATE=${RESTORE_DRILL_STATE:-$BACKUP_ROOT/.restore-drill/last-success.env}
MAX_RESTORE_DRILL_AGE_SECONDS=${MAX_RESTORE_DRILL_AGE_SECONDS:-777600}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

required_containers=(
  supabase-db
  supabase-auth
  supabase-rest
  realtime-dev.supabase-realtime
  supabase-storage
  supabase-imgproxy
  supabase-meta
  supabase-edge-functions
  supabase-pooler
  supabase-kong
  supabase-studio
)

for container in "${required_containers[@]}"; do
  health=$(docker inspect --format '{{.State.Health.Status}}' "$container")
  [[ "$health" == healthy ]]
done

disk_percent=$(df -P / | awk 'NR == 2 {gsub("%", "", $5); print $5}')
((disk_percent < MAX_DISK_PERCENT))

available_memory_kib=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
((available_memory_kib >= MIN_AVAILABLE_MEMORY_KIB))

account_sync_ready=$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 \
  -U supabase_admin -d postgres -Atqc \
  "select
     to_regclass('public.authenticator_accounts') is not null
     and (
       select relrowsecurity and relforcerowsecurity
       from pg_class
       where oid = 'public.authenticator_accounts'::regclass
     )
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
     and not has_function_privilege(
       'anon', 'public.list_authenticator_accounts()', 'execute'
     )
     and (select prosecdef from pg_proc where oid =
       'public.list_authenticator_accounts()'::regprocedure)
     and (select prosecdef from pg_proc where oid =
       'public.upsert_authenticator_account(uuid,bigint,jsonb)'::regprocedure)
     and (select prosecdef from pg_proc where oid =
       'public.delete_authenticator_account(uuid,bigint)'::regprocedure)
     and (select prosecdef from pg_proc where oid =
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
       select 1 from pg_policy
       where polrelid = 'realtime.messages'::regclass
         and polcmd = 'a'
         and 'authenticated'::regrole = any (polroles)
     )
     and not exists (
       select 1 from pg_publication_tables
       where schemaname = 'public'
         and tablename = 'authenticator_accounts'
     )
     and exists (
       select 1 from pg_extension where extname = 'supabase_vault'
     )
     and to_regclass('public.encrypted_vault_snapshots') is null
     and to_regclass('public.synced_accounts') is null
     and to_regclass('public.authenticator_device_sessions') is null
     and to_regclass('public.authenticator_device_keys') is null
     and to_regclass('public.authenticator_device_key_wraps') is null
     and to_regclass('private.encrypted_vault_membership_verifiers') is null
     and to_regprocedure(
       'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'
     ) is null")
[[ "$account_sync_ready" == t ]]

if [[ -f "$STACK_ENV" && -n "$API_ORIGIN" ]]; then
  public_key=''
  for key_name in SUPABASE_PUBLISHABLE_KEY PUBLISHABLE_KEY ANON_KEY; do
    key_line=$(grep -m1 "^${key_name}=" "$STACK_ENV" || true)
    if [[ -n "$key_line" ]]; then
      public_key=${key_line#*=}
      if [[ "$public_key" == \"*\" && "$public_key" == *\" ]]; then
        public_key=${public_key:1:${#public_key}-2}
      elif [[ "$public_key" == \'*\' && "$public_key" == *\' ]]; then
        public_key=${public_key:1:${#public_key}-2}
      fi
      break
    fi
  done
  [[ -n "$public_key" ]]
  api_status=$(curl --connect-timeout 10 --max-time 20 -sS \
    -o /dev/null -w '%{http_code}' -H "apikey: $public_key" \
    "${API_ORIGIN%/}/auth/v1/health")
  [[ "$api_status" == 200 ]]
fi

if [[ -n "$RECOVERY_ORIGIN" ]]; then
  recovery_status=$(curl --connect-timeout 10 --max-time 20 -sS \
    -o /dev/null -w '%{http_code}' "${RECOVERY_ORIGIN%/}/reset-password/")
  [[ "$recovery_status" == 200 ]]
fi

latest_backup=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
  -name 'supabase-*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 || true)
[[ -n "$latest_backup" ]]
latest_epoch=${latest_backup%% *}
latest_epoch=${latest_epoch%.*}
backup_age=$(( $(date +%s) - latest_epoch ))
((backup_age <= MAX_BACKUP_AGE_SECONDS))

"$SCRIPT_DIR/check_restore_drill_state.sh" \
  "$RESTORE_DRILL_STATE" "$MAX_RESTORE_DRILL_AGE_SECONDS" >/dev/null

printf '%s\n' \
  'Supabase production health pass: containers, capacity, Vault/RPC/private-Realtime contract, HTTPS, backup và restore-drill freshness.'
