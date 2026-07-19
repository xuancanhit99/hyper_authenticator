#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/supabase/deploy_nginx_proxy_manager_upgrade.sh"

if [[ ! -x "$SCRIPT" ]]; then
  printf 'Thiếu executable NPM production deployment harness: %s\n' "$SCRIPT" >&2
  exit 66
fi
bash -n "$SCRIPT"
for pattern in \
  '--allow-production-nginx-proxy-manager-upgrade' \
  '.upgrade-deploy.lock' \
  'sha256sum --check SHA256SUMS' \
  'compose.original.yaml' \
  'compose.candidate.yaml' \
  'docker compose up -d --no-deps "$APP_SERVICE"' \
  'http://127.0.0.1:81/api/' \
  'docker exec "$APP_CONTAINER" nginx -t' \
  '--allow-production-nginx-proxy-manager-route-probe' \
  'NPM automatic rollback' \
  'wait_for_runtime "$current_image_id" "$current_version"' \
  'Rollback Compose giữ mode 0600'; do
  grep -Fq -- "$pattern" "$SCRIPT"
done

if grep -Eq 'docker compose (down|stop|restart)|docker (volume|network) (rm|prune)' \
  "$SCRIPT"; then
  printf '%s\n' 'NPM production deployment không được dừng DB/network/volume.' >&2
  exit 1
fi
if ! grep -Fq 'cmp -s compose.yaml "$MAINTENANCE_BUNDLE/compose.original.yaml"' \
  "$SCRIPT"; then
  printf '%s\n' 'NPM production deployment phải fail khi Compose đã drift.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM production-deploy contract pass: exact bundle/image, route gate và auto-rollback.'
