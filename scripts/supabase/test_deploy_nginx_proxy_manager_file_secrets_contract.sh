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

printf '%s\n' \
  'NPM file-secret deploy contract pass: drift/checksum, DB-first rollout, post-gate và rollback.'
