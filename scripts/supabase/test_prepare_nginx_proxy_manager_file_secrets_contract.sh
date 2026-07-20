#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/supabase/prepare_nginx_proxy_manager_file_secrets.sh"

bash -n "$SCRIPT"
for contract in \
  '--allow-nginx-proxy-manager-file-secret-preparation' \
  'docker compose config --format json' \
  'backup_nginx_proxy_manager.sh' \
  'rehearse_nginx_proxy_manager_backup.sh' \
  'rehearse_nginx_proxy_manager_upgrade.sh' \
  'render_nginx_proxy_manager_file_secrets.py' \
  'test_nginx_proxy_manager_route_matrix.sh' \
  'BUNDLE_FORMAT=hyper-auth-nginx-proxy-manager-file-secrets-v1' \
  'chmod 0400'; do
  grep -Fq -- "$contract" "$SCRIPT" || {
    printf 'NPM file-secret preparation thiếu contract: %s\n' "$contract" >&2
    exit 1
  }
done
if grep -Eq 'docker compose (up|down|stop|restart|rm)' "$SCRIPT"; then
  printf '%s\n' 'Preparation không được mutate production Compose runtime.' >&2
  exit 1
fi
if grep -Eq '(^|[[:space:]])(rm[[:space:]]+-rf|docker[[:space:]]+volume[[:space:]]+rm)' \
  "$SCRIPT"; then
  printf '%s\n' 'Preparation không được có destructive cleanup primitive.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM file-secret preparation contract pass: backup/restore/canary/route và no production mutation.'
