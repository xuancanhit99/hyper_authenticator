#!/bin/sh
set -eu

fail() {
  printf '%s\n' "Không thể khởi động Flutter Web: $1" >&2
  exit 78
}

supabase_url=${SUPABASE_URL:-}

[ -n "$supabase_url" ] || fail 'thiếu SUPABASE_URL dùng để tạo CSP'

# PublicRuntimeConfig chấp nhận origin có path `/`; CSP dùng dạng không slash.
case "$supabase_url" in
  */) supabase_url=${supabase_url%/} ;;
esac

host_label='[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?'
if ! printf '%s' "$supabase_url" |
    grep -Eq "^https://${host_label}(\.${host_label})*(:[0-9]{1,5})?$"; then
  fail 'SUPABASE_URL phải là HTTPS origin không chứa path, user info, query hoặc fragment'
fi

supabase_wss="wss://${supabase_url#https://}"

umask 077
sed \
  -e "s|@@SUPABASE_HTTPS_ORIGIN@@|$supabase_url|g" \
  -e "s|@@SUPABASE_WSS_ORIGIN@@|$supabase_wss|g" \
  /opt/web-app/nginx-site.conf.template \
  > /tmp/web-app-site.conf

exec "$@"
