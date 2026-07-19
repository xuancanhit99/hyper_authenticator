#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/supabase/prepare_nginx_proxy_manager_upgrade.sh"

if [[ ! -x "$SCRIPT" ]]; then
  printf 'Thiếu executable NPM upgrade-preparation harness: %s\n' "$SCRIPT" >&2
  exit 66
fi
bash -n "$SCRIPT"
for pattern in \
  '.upgrade-prepare.lock' \
  'NPM_IMAGE' \
  'REVIEWED_NPM_TARGET_IMAGE' \
  '--allow-production-nginx-proxy-manager-route-probe' \
  '--allow-nginx-proxy-manager-backup' \
  '--allow-isolated-nginx-proxy-manager-restore' \
  '--allow-isolated-nginx-proxy-manager-upgrade' \
  'compose.original.yaml' \
  'compose.candidate.yaml' \
  'candidate.normalized.yaml' \
  'SHA256SUMS' \
  'production Compose/container chưa bị thay đổi'; do
  grep -Fq -- "$pattern" "$SCRIPT"
done
if grep -Eq 'docker compose (up|stop|restart|down|rm)|mv .*compose\.yaml' "$SCRIPT"; then
  printf '%s\n' 'NPM preparation harness không được mutate production Compose/runtime.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM upgrade-preparation contract pass: backup/canary/routes và non-mutating candidate.'
