#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HTTP_TOP="$ROOT/supabase/nginx-proxy-manager/http_top.conf"
SERVER_PROXY="$ROOT/supabase/nginx-proxy-manager/server_proxy.conf"
PRODUCTION_PIN="$ROOT/supabase/nginx-proxy-manager/PRODUCTION_PIN"

for path in "$HTTP_TOP" "$SERVER_PROXY" "$PRODUCTION_PIN"; do
  if [[ ! -f "$path" ]]; then
    printf 'Thiếu NPM timing config: %s\n' "$path" >&2
    exit 66
  fi
done

grep -Fq 'supabase-api.vnpay.dev/auth/v1/health 1;' "$HTTP_TOP"
grep -Fq 'log_format hyper_auth_supabase_timing escape=json' "$HTTP_TOP"
grep -Fq 'hyper-auth-supabase-timing_access.log' "$SERVER_PROXY"
grep -Fq 'if=$hyper_auth_supabase_health_timing_enabled;' "$SERVER_PROXY"
if [[ $(grep -Ec '^[A-Z_]+=[^[:space:]]+$' "$PRODUCTION_PIN") != 5 ]] ||
  [[ $(grep -Ec '^[A-Z_]*IMAGE=[a-z0-9./-]+@sha256:[0-9a-f]{64}$' \
    "$PRODUCTION_PIN") != 2 ]]; then
  printf '%s\n' 'NPM production pin không có exact version/image digest contract.' >&2
  exit 1
fi

logged_variables=$(awk '
  /^log_format hyper_auth_supabase_timing / { capture = 1 }
  capture { print }
  capture && /;$/ { exit }
' "$HTTP_TOP" | grep -Eo '\$[A-Za-z_][A-Za-z0-9_]*' | LC_ALL=C sort -u)
expected_variables=$(printf '%s\n' \
  '$request_id' \
  '$request_time' \
  '$status' \
  '$time_iso8601' \
  '$upstream_connect_time' \
  '$upstream_header_time' \
  '$upstream_response_time' \
  '$upstream_status' | LC_ALL=C sort)
if [[ "$logged_variables" != "$expected_variables" ]]; then
  printf '%s\n' 'NPM timing log variable allowlist không khớp.' >&2
  diff -u \
    <(printf '%s\n' "$expected_variables") \
    <(printf '%s\n' "$logged_variables") >&2 || true
  exit 1
fi

if grep -Eq '\$(remote_addr|http_|request_body|request_uri|args|query_string|cookie)' \
  <(awk '
    /^log_format hyper_auth_supabase_timing / { capture = 1 }
    capture { print }
    capture && /;$/ { exit }
  ' "$HTTP_TOP"); then
  printf '%s\n' 'NPM timing log chứa request/client field bị cấm.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM timing contract pass: exact route, rotated access log và field allowlist.'
