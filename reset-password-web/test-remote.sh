#!/bin/sh
set -eu

origin=${1:-}
case "$origin" in
  https://*/*|https://*) ;;
  *)
    printf '%s\n' 'Cách dùng: test-remote.sh https://recovery.example.com' >&2
    exit 64
    ;;
esac

origin=${origin%/}
case "${origin#https://}" in
  */*|*\?*|*\#*|*@*)
    printf '%s\n' 'Origin không được chứa path, query hoặc fragment.' >&2
    exit 64
    ;;
esac
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-recovery-remote.XXXXXX")
chmod 700 "$tmp_dir"

cleanup() {
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT INT TERM

curl --connect-timeout 10 --max-time 20 -fsS \
  -D "$tmp_dir/headers" \
  -o "$tmp_dir/page" \
  "$origin/reset-password/"

tr '[:upper:]' '[:lower:]' < "$tmp_dir/headers" > "$tmp_dir/headers.lower"
grep -Eq '^http/[0-9.]+ 200' "$tmp_dir/headers.lower"
grep -Eq '^cache-control: .*no-store' "$tmp_dir/headers.lower"
grep -Eq '^content-security-policy:' "$tmp_dir/headers.lower"
grep -Eq '^referrer-policy: no-referrer' "$tmp_dir/headers.lower"
grep -Eq '^strict-transport-security:' "$tmp_dir/headers.lower"
grep -Fq 'id="reset-password-form"' "$tmp_dir/page"

curl --connect-timeout 10 --max-time 20 -fsS \
  "$origin/healthz" | grep -qx healthy
curl --connect-timeout 10 --max-time 20 -fsS \
  "$origin/style.css" >/dev/null
curl --connect-timeout 10 --max-time 20 -fsS \
  "$origin/env-config.js" > "$tmp_dir/env-config.js"
sed -n "s/.*atob('\([^']*\)').*/\1/p" "$tmp_dir/env-config.js" \
  > "$tmp_dir/config-values.base64"
[ "$(wc -l < "$tmp_dir/config-values.base64" | tr -d ' ')" -eq 2 ]
tail -n 1 "$tmp_dir/config-values.base64" | base64 -d \
  > "$tmp_dir/publishable-key"
publishable_key=$(cat "$tmp_dir/publishable-key")
case "$publishable_key" in
  sb_publishable_*) ;;
  eyJ*.*.*)
    payload=$(printf '%s' "$publishable_key" | cut -d. -f2 | tr '_-' '/+')
    case $((${#payload} % 4)) in
      2) payload="${payload}==" ;;
      3) payload="${payload}=" ;;
    esac
    printf '%s' "$payload" | base64 -d > "$tmp_dir/jwt-payload" 2>/dev/null
    grep -Eq '"role"[[:space:]]*:[[:space:]]*"anon"' "$tmp_dir/jwt-payload"
    ;;
  *)
    printf '%s\n' 'Public runtime config không chứa publishable/anon key hợp lệ.' >&2
    exit 1
    ;;
esac
unset publishable_key payload

curl --connect-timeout 10 --max-time 20 -fsS \
  "$origin/email-templates/recovery.html" \
  | grep -Fq '{{ .TokenHash }}'

printf '%s\n' 'Remote recovery HTTPS/header/config/template checks pass.'
