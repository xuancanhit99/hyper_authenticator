#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SERVICE="$ROOT/supabase/systemd/hyper-auth-nginx-proxy-manager-routes.service"
TIMER="$ROOT/supabase/systemd/hyper-auth-nginx-proxy-manager-routes.timer"
SCRIPT="$ROOT/scripts/supabase/test_nginx_proxy_manager_route_matrix.sh"

for path in "$SERVICE" "$TIMER" "$SCRIPT"; do
  if [[ ! -f "$path" ]]; then
    printf 'Thiếu NPM route-timer contract file: %s\n' "$path" >&2
    exit 66
  fi
done

grep -Fq 'User=root' "$SERVICE"
grep -Fq \
  'ConditionFileIsExecutable=/usr/local/lib/hyper-authenticator/test_nginx_proxy_manager_route_matrix.sh' \
  "$SERVICE"
grep -Fq 'ProtectSystem=strict' "$SERVICE"
grep -Fq 'PrivateTmp=true' "$SERVICE"
grep -Fq 'NoNewPrivileges=true' "$SERVICE"
grep -Fq 'TimeoutStartSec=10m' "$SERVICE"
grep -Fq \
  'ExecStart=/usr/local/lib/hyper-authenticator/test_nginx_proxy_manager_route_matrix.sh /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf --allow-production-nginx-proxy-manager-route-probe' \
  "$SERVICE"
grep -Fq 'OnUnitActiveSec=1h' "$TIMER"
grep -Fq 'RandomizedDelaySec=5m' "$TIMER"
grep -Fq 'Persistent=true' "$TIMER"
grep -Fq 'Unit=hyper-auth-nginx-proxy-manager-routes.service' "$TIMER"

if grep -Eq 'Environment(File)?=.*(KEY|PASSWORD|TOKEN|SECRET)' "$SERVICE"; then
  printf '%s\n' 'NPM route service không được inject credential environment.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM route timer contract pass: hourly persistent gate, redacted manifests và systemd sandbox.'
