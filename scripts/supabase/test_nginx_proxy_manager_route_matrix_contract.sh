#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/supabase/test_nginx_proxy_manager_route_matrix.sh"

if [[ ! -x "$SCRIPT" ]]; then
  printf 'Thiếu executable NPM route-matrix harness: %s\n' "$SCRIPT" >&2
  exit 66
fi
bash -n "$SCRIPT"
for pattern in \
  'SELECT domain_names FROM proxy_host' \
  'SELECT domain_names FROM redirection_host' \
  'SELECT domain_names FROM dead_host' \
  'SELECT COUNT(*) FROM stream' \
  'https://$domain/' \
  'route_id=' \
  'expected_status' \
  'exception_status' \
  'matched_exceptions' \
  'matched_exceptions != exception_count' \
  'manifest_mode' \
  'source "$SCRIPT_DIR/nginx_proxy_manager_database.sh"' \
  'npm_database_exec "$DB_CONTAINER"'; do
  grep -Fq -- "$pattern" "$SCRIPT"
done
if grep -E 'printf .*(\$domain|\$url|\$manifest_host)' "$SCRIPT" |
  grep -Fvq 'sha256sum'; then
  printf '%s\n' 'NPM route-matrix harness không được in hostname hoặc URL.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM route-matrix contract pass: full discovery, critical status và redacted output.'
