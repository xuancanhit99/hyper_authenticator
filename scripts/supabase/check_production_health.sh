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

docker exec supabase-db psql -X -v ON_ERROR_STOP=1 \
  -U supabase_admin -d postgres -Atqc \
  "select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.encrypted_vault_snapshots'::regclass" \
  | grep -qx t

session_guard_ready=$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 \
  -U supabase_admin -d postgres -Atqc \
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

device_registry_ready=$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 \
  -U supabase_admin -d postgres -Atqc \
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
       'is_current_auth_session_active'
       in pg_get_functiondef(
         'public.revoke_authenticator_device_session(uuid)'::regprocedure
       )
     ) > 0
     and position(
       'delete from auth.sessions'
       in lower(pg_get_functiondef(
         'public.revoke_authenticator_device_session(uuid)'::regprocedure
       ))
     ) > 0")
[[ "$device_registry_ready" == t ]]

device_wrap_ready=$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 \
  -U supabase_admin -d postgres -Atqc \
  "select
     to_regclass('public.synced_accounts') is null
     and to_regclass('public.authenticator_device_keys') is not null
     and to_regclass('public.authenticator_device_key_wraps') is not null
     and to_regclass('private.encrypted_vault_membership_verifiers') is not null
     and not has_table_privilege(
       'authenticated', 'public.authenticator_device_keys', 'select'
     )
     and not has_table_privilege(
       'authenticated', 'public.authenticator_device_key_wraps', 'select'
     )
     and not has_table_privilege(
       'authenticated', 'private.encrypted_vault_membership_verifiers', 'select'
     )
     and exists (
       select 1 from pg_proc
       where oid = 'public.publish_encrypted_vault_snapshot_v2(bigint,bigint,text,smallint,text,text,text,text,smallint,text,text,text)'::regprocedure
         and prosecdef
     )
     and position(
       'for update'
       in lower(pg_get_functiondef(
         'public.publish_encrypted_vault_snapshot_v2(bigint,bigint,text,smallint,text,text,text,text,smallint,text,text,text)'::regprocedure
       ))
     ) > 0
     and position(
       'p_expected_revision <> 0'
       in pg_get_functiondef(
         'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'::regprocedure
       )
     ) > 0
     and position(
       'p_expected_revision is null'
       in lower(pg_get_functiondef(
         'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'::regprocedure
       ))
     ) > 0
     and exists (
       select 1 from pg_proc
       where oid = 'public.begin_authenticator_device_key_enrollment(uuid,text,text,text)'::regprocedure
         and prosecdef
     )
     and to_regprocedure(
       'public.begin_authenticator_device_key_enrollment(uuid,text,text)'
     ) is null
     and exists (
       select 1 from pg_proc
       where oid = 'public.publish_authenticator_device_key_wrap(uuid,text,bigint,smallint,text,text,text,text,text,text,text,text)'::regprocedure
         and prosecdef
     )
     and exists (
       select 1 from pg_proc
       where oid = 'public.rotate_encrypted_vault_device_keys(bigint,bigint,text,smallint,text,text,text,text,smallint,text,text,text,text,jsonb,uuid[])'::regprocedure
         and prosecdef
     )")
[[ "$device_wrap_ready" == t ]]

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
  'Supabase production health pass: containers, capacity, active-session/device-registry/device-wrap guard, HTTPS, backup và restore-drill freshness.'
