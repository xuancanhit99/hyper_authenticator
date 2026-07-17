#!/bin/sh
set -eu

fail() {
  printf '%s\n' "Không thể khởi động trang recovery: $1" >&2
  exit 78
}

supabase_url=${SUPABASE_URL:-}
publishable_key=${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-}}

[ -n "$supabase_url" ] || fail 'thiếu SUPABASE_URL'
[ -n "$publishable_key" ] || fail 'thiếu SUPABASE_PUBLISHABLE_KEY'

if ! printf '%s' "$supabase_url" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$'; then
  fail 'SUPABASE_URL phải là HTTPS origin, không chứa path, query hoặc fragment'
fi

if [ "${#publishable_key}" -lt 20 ] || [ "${#publishable_key}" -gt 4096 ]; then
  fail 'public key có độ dài không hợp lệ'
fi

if printf '%s' "$publishable_key" | grep -Eq '[[:space:]]'; then
  fail 'public key không được chứa whitespace'
fi

case "$publishable_key" in
  sb_secret_*|*service_role*)
    fail 'chỉ được dùng publishable/anon key; server secret bị từ chối'
    ;;
esac

case "$publishable_key" in
  eyJ*.*.*)
    jwt_payload=$(printf '%s' "$publishable_key" | cut -d. -f2 | tr '_-' '/+')
    case $((${#jwt_payload} % 4)) in
      2) jwt_payload="${jwt_payload}==" ;;
      3) jwt_payload="${jwt_payload}=" ;;
    esac
    decoded_payload=$(printf '%s' "$jwt_payload" | base64 -d 2>/dev/null || true)
    if printf '%s' "$decoded_payload" | grep -Eq '"role"[[:space:]]*:[[:space:]]*"service_role"'; then
      fail 'legacy service-role JWT bị từ chối'
    fi
    ;;
esac

url_base64=$(printf '%s' "$supabase_url" | base64 | tr -d '\n')
key_base64=$(printf '%s' "$publishable_key" | base64 | tr -d '\n')

umask 077
printf '%s\n' \
  "window.__RESET_PASSWORD_CONFIG__ = Object.freeze({" \
  "  supabaseUrl: atob('$url_base64')," \
  "  supabasePublishableKey: atob('$key_base64')" \
  "});" \
  > /tmp/reset-password-env.js

sed "s|@@SUPABASE_ORIGIN@@|$supabase_url|g" \
  /opt/reset-password/nginx-site.conf.template \
  > /tmp/reset-password-site.conf

exec "$@"
