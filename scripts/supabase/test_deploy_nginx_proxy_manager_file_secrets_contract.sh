#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/supabase/deploy_nginx_proxy_manager_file_secrets.sh"

bash -n "$SCRIPT"
for contract in \
  '--allow-production-nginx-proxy-manager-file-secrets' \
  'BUNDLE_FORMAT=hyper-auth-nginx-proxy-manager-file-secrets-v1' \
  'cmp -s compose.yaml' \
  'cmp -s .env' \
  'sha256sum --check SHA256SUMS' \
  'NPM_FILE_SECRET_MAX_AGE_SECONDS' \
  'Chạy lại preparation' \
  'docker compose up -d --no-deps --force-recreate "$DB_SERVICE"' \
  'docker compose up -d --no-deps --force-recreate "$APP_SERVICE"' \
  'file_secret_gate' \
  'NPM automatic rollback' \
  'runtime_gate' \
  'systemctl is-active --quiet "$ROUTE_TIMER"'; do
  grep -Fq -- "$contract" "$SCRIPT" || {
    printf 'NPM file-secret deploy thiếu contract: %s\n' "$contract" >&2
    exit 1
  }
done
for forbidden in \
  'docker compose down' 'docker volume rm' 'docker network rm' \
  'docker system prune' 'rm -rf'; do
  if grep -Fq -- "$forbidden" "$SCRIPT"; then
    printf 'NPM file-secret deploy chứa primitive bị cấm: %s\n' "$forbidden" >&2
    exit 1
  fi
done
db_recreates=$(grep -Fc \
  'docker compose up -d --no-deps --force-recreate "$DB_SERVICE"' "$SCRIPT")
app_recreates=$(grep -Fc \
  'docker compose up -d --no-deps --force-recreate "$APP_SERVICE"' "$SCRIPT")
if ((db_recreates < 2 || app_recreates < 2)); then
  printf '%s\n' 'Deploy và rollback đều phải recreate DB/app.' >&2
  exit 1
fi
transaction_line=$(grep -n '^set +e$' "$SCRIPT" | head -1 | cut -d: -f1)
route_install_line=$(grep -n 'install -m 0755 "$BUNDLE/route-harness/$name"' \
  "$SCRIPT" | head -1 | cut -d: -f1)
secret_move_line=$(grep -n 'mv "$COMPOSE_DIR/.secrets.file-secrets.\$\$"' \
  "$SCRIPT" | head -1 | cut -d: -f1)
config_move_line=$(grep -n 'mv "$COMPOSE_DIR/.compose.file-secrets.\$\$" compose.yaml' \
  "$SCRIPT" | head -1 | cut -d: -f1)
if [[ -z "$transaction_line" || -z "$route_install_line" ||
  -z "$secret_move_line" || -z "$config_move_line" ]] ||
  ((transaction_line >= route_install_line || transaction_line >= secret_move_line ||
    transaction_line >= config_move_line)); then
  printf '%s\n' 'Mọi route/secret/config mutation phải nằm trong transaction rollback.' >&2
  exit 1
fi
if grep -Eq '^(route_installed|secrets_installed|config_installed)=' "$SCRIPT"; then
  printf '%s\n' 'Rollback không được phụ thuộc flag không propagate khỏi subshell.' >&2
  exit 1
fi
grep -Fq 'source "$BUNDLE/route-harness/nginx_proxy_manager_database.sh"' "$SCRIPT"
grep -Fq 'giữ route snapshot tại %s' "$SCRIPT"

printf '%s\n' \
  'NPM file-secret deploy contract pass: drift/checksum, atomic mutation, DB-first post-gate và rollback.'
