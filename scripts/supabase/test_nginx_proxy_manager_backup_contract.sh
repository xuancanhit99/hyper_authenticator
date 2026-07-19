#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BACKUP="$ROOT/scripts/supabase/backup_nginx_proxy_manager.sh"
RESTORE="$ROOT/scripts/supabase/rehearse_nginx_proxy_manager_backup.sh"
UPGRADE="$ROOT/scripts/supabase/rehearse_nginx_proxy_manager_upgrade.sh"
DATABASE_LIBRARY="$ROOT/scripts/supabase/nginx_proxy_manager_database.sh"
DATABASE_PAYLOAD="$ROOT/scripts/supabase/npm_database_exec_container.sh"

for path in "$BACKUP" "$RESTORE" "$UPGRADE" "$DATABASE_LIBRARY" \
  "$DATABASE_PAYLOAD"; do
  if [[ ! -x "$path" ]]; then
    printf 'Thiếu executable NPM backup contract: %s\n' "$path" >&2
    exit 66
  fi
  bash -n "$path"
done

for pattern in \
  'source "$SCRIPT_DIR/nginx_proxy_manager_database.sh"' \
  'npm_database_exec "$DB_CONTAINER"'; do
  grep -Fq -- "$pattern" "$BACKUP"
done

for pattern in \
  '--single-transaction' \
  "--exclude='data/mysql'" \
  "--exclude='data/app/logs'" \
  'DB_IMAGE_ID=$db_image' \
  'DB_NAME=$db_name' \
  'sha256sum --check SHA256SUMS'; do
  grep -Fq -- "$pattern" "$BACKUP"
done

for pattern in \
  '--network none' \
  'docker image inspect "$db_image_id"' \
  '--batch --skip-column-names -e "SELECT 1"' \
  '--database="$1"' \
  'table_name IN'; do
  grep -Fq -- "$pattern" "$RESTORE"
done
for table_name in user proxy_host certificate setting; do
  grep -Fq -- "\\\"$table_name\\\"" "$RESTORE"
done

if grep -Fq 'mariadb-admin ping' "$RESTORE"; then
  printf '%s\n' 'NPM restore không được dùng unauthenticated readiness ping.' >&2
  exit 1
fi

for pattern in \
  'docker network create --internal' \
  '--volume "$sandbox/data/app:/data"' \
  '--volume "$sandbox/data/letsencrypt:/etc/letsencrypt"' \
  'http://127.0.0.1:81/api/' \
  'docker exec "$app_container" nginx -t' \
  'DB_MYSQL_PASSWORD__FILE=/run/secrets/npm_db_password' \
  'MARIADB_ROOT_PASSWORD_FILE=/run/secrets/npm_db_root_password' \
  'MARIADB_PASSWORD_FILE=/run/secrets/npm_db_password' \
  "grep -Eq '^(MYSQL|MARIADB|DB_MYSQL)_[A-Z_]*PASSWORD='" \
  '/run/secrets/npm_db_root_password' \
  '/run/secrets/npm_db_password' \
  "'{{json .HostConfig.PortBindings}}'" \
  'container rm --force --volumes'; do
  grep -Fq -- "$pattern" "$UPGRADE"
done
if grep -Fq 'mariadb-admin ping' "$UPGRADE"; then
  printf '%s\n' 'NPM upgrade không được dùng unauthenticated readiness ping.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM backup contract pass: private backup, isolated restore và no-port upgrade canary.'
