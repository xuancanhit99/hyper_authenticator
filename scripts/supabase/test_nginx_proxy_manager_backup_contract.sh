#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BACKUP="$ROOT/scripts/supabase/backup_nginx_proxy_manager.sh"
RESTORE="$ROOT/scripts/supabase/rehearse_nginx_proxy_manager_backup.sh"

for path in "$BACKUP" "$RESTORE"; do
  if [[ ! -x "$path" ]]; then
    printf 'Thiếu executable NPM backup contract: %s\n' "$path" >&2
    exit 66
  fi
  bash -n "$path"
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

printf '%s\n' \
  'NPM backup contract pass: private transactional backup và isolated authenticated restore.'
