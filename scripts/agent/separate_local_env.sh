#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CLIENT_ENV=${1:-"$ROOT/.env"}
SERVER_ENV=${2:-"$ROOT/.env.server"}
CONFIRMATION=${3:-}
EXPECTED_CONFIRMATION=SEPARATE_LOCAL_SERVER_CONFIG

server_keys=(
  REMOTE_HOST
  REMOTE_PORT
  REMOTE_USER
  SSH_KEY_PATH
  REMOTE_COMPOSE_DIR_SUPABASE
)

usage() {
  printf '%s\n' \
    'Usage: scripts/agent/separate_local_env.sh [CLIENT_ENV] [SERVER_ENV] CONFIRMATION' \
    "Confirmation bắt buộc: $EXPECTED_CONFIRMATION" >&2
}

if [[ "$CONFIRMATION" != "$EXPECTED_CONFIRMATION" ]]; then
  usage
  exit 64
fi
if [[ ! -f "$CLIENT_ENV" || -L "$CLIENT_ENV" ]]; then
  printf '%s\n' 'Client env phải là regular file, không phải symlink.' >&2
  exit 66
fi
if [[ -e "$SERVER_ENV" || -L "$SERVER_ENV" ]]; then
  printf '%s\n' 'Server env đã tồn tại; không ghi đè cấu hình vận hành.' >&2
  exit 73
fi

file_mode=$(stat -f '%Lp' "$CLIENT_ENV" 2>/dev/null || stat -c '%a' "$CLIENT_ENV")
if (( (8#$file_mode & 077) != 0 )); then
  printf 'Client env phải có mode 0600 hoặc chặt hơn; hiện tại là %s.\n' \
    "$file_mode" >&2
  exit 77
fi

for key in "${server_keys[@]}"; do
  count=$(awk -F= -v key="$key" '$1 == key { count += 1 } END { print count + 0 }' \
    "$CLIENT_ENV")
  if [[ "$count" != 1 ]]; then
    printf 'Client env phải chứa đúng một khai báo %s trước khi tách.\n' "$key" >&2
    exit 65
  fi
done

plaintext_count=$(awk -F= '$1 == "ALLOW_INSECURE_PLAINTEXT_SYNC" { count += 1 } END { print count + 0 }' \
  "$CLIENT_ENV")
if [[ "$plaintext_count" -gt 1 ]]; then
  printf '%s\n' 'ALLOW_INSECURE_PLAINTEXT_SYNC bị khai báo lặp.' >&2
  exit 65
fi
if [[ "$plaintext_count" == 1 ]]; then
  plaintext_value=$(awk -F= '$1 == "ALLOW_INSECURE_PLAINTEXT_SYNC" { print substr($0, index($0, "=") + 1) }' \
    "$CLIENT_ENV")
  if [[ "$plaintext_value" != false ]]; then
    printf '%s\n' 'Chỉ cho phép tách cấu hình khi plaintext sync được đặt false.' >&2
    exit 65
  fi
fi

umask 077
client_temp=$(mktemp "${CLIENT_ENV}.tmp.XXXXXX")
server_temp=$(mktemp "${SERVER_ENV}.tmp.XXXXXX")
cleanup() {
  rm -f "$client_temp" "$server_temp"
}
trap cleanup EXIT INT TERM

awk '
  BEGIN {
    server["REMOTE_HOST"] = 1
    server["REMOTE_PORT"] = 1
    server["REMOTE_USER"] = 1
    server["SSH_KEY_PATH"] = 1
    server["REMOTE_COMPOSE_DIR_SUPABASE"] = 1
  }
  {
    key = $0
    sub(/=.*/, "", key)
    if (!(key in server)) print
  }
' "$CLIENT_ENV" >"$client_temp"

if [[ "$plaintext_count" == 0 ]]; then
  if [[ -s "$client_temp" ]] && [[ $(tail -c 1 "$client_temp" | wc -l) -eq 0 ]]; then
    printf '\n' >>"$client_temp"
  fi
  printf 'ALLOW_INSECURE_PLAINTEXT_SYNC=false\n' >>"$client_temp"
fi

{
  printf '%s\n' '# Cấu hình vận hành server/SSH; không được truyền vào Flutter build.'
  for key in "${server_keys[@]}"; do
    awk -v key="$key" 'index($0, key "=") == 1 { print; exit }' "$CLIENT_ENV"
  done
} >"$server_temp"

chmod 0600 "$client_temp" "$server_temp"
mv "$server_temp" "$SERVER_ENV"
mv "$client_temp" "$CLIENT_ENV"
trap - EXIT

printf '%s\n' '✓ Đã tách 5 biến server/SSH khỏi client env.'
printf '%s\n' '✓ Client env đặt ALLOW_INSECURE_PLAINTEXT_SYNC=false.'
printf '%s\n' '✓ Hai file local giữ mode 0600; không in giá trị cấu hình.'
