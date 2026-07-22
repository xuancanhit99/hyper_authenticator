#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/agent/separate_local_env.sh"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-env-test.XXXXXX")
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

client_env="$WORK_DIR/client.env"
server_env="$WORK_DIR/server.env"
cat >"$client_env" <<'EOF'
SUPABASE_URL=https://api.example.com
SUPABASE_PUBLISHABLE_KEY=sb_publishable_0123456789012345678901_01234567
PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/
REMOTE_HOST=server.example.com
REMOTE_PORT=22
REMOTE_USER=operator
SSH_KEY_PATH=/secure/operator-key
REMOTE_COMPOSE_DIR_SUPABASE=/opt/stacks/supabase
EOF
chmod 0600 "$client_env"

"$SCRIPT" "$client_env" "$server_env" SEPARATE_LOCAL_SERVER_CONFIG >/dev/null

for key in REMOTE_HOST REMOTE_PORT REMOTE_USER SSH_KEY_PATH REMOTE_COMPOSE_DIR_SUPABASE; do
  if grep -q "^${key}=" "$client_env" || ! grep -q "^${key}=" "$server_env"; then
    printf 'Tách cấu hình thất bại với key %s.\n' "$key" >&2
    exit 1
  fi
done
if ! grep -qx 'ALLOW_INSECURE_PLAINTEXT_SYNC=false' "$client_env"; then
  printf '%s\n' 'Client env không có plaintext-sync guard an toàn.' >&2
  exit 1
fi
if [[ $(stat -f '%Lp' "$client_env" 2>/dev/null || stat -c '%a' "$client_env") != 600 ||
  $(stat -f '%Lp' "$server_env" 2>/dev/null || stat -c '%a' "$server_env") != 600 ]]; then
  printf '%s\n' 'Env sau khi tách không giữ mode 0600.' >&2
  exit 1
fi

before=$(shasum -a 256 "$client_env" | awk '{ print $1 }')
if "$SCRIPT" "$client_env" "$server_env" SEPARATE_LOCAL_SERVER_CONFIG >/dev/null 2>&1; then
  printf '%s\n' 'Script phải từ chối ghi đè server env.' >&2
  exit 1
fi
after=$(shasum -a 256 "$client_env" | awk '{ print $1 }')
if [[ "$before" != "$after" ]]; then
  printf '%s\n' 'Client env bị đổi khi server env đã tồn tại.' >&2
  exit 1
fi

unsafe_client="$WORK_DIR/unsafe-client.env"
unsafe_server="$WORK_DIR/unsafe-server.env"
sed 's/ALLOW_INSECURE_PLAINTEXT_SYNC=false/ALLOW_INSECURE_PLAINTEXT_SYNC=true/' \
  "$client_env" >"$unsafe_client"
for key in REMOTE_HOST REMOTE_PORT REMOTE_USER SSH_KEY_PATH REMOTE_COMPOSE_DIR_SUPABASE; do
  grep "^${key}=" "$server_env" >>"$unsafe_client"
done
chmod 0600 "$unsafe_client"
unsafe_before=$(shasum -a 256 "$unsafe_client" | awk '{ print $1 }')
if "$SCRIPT" "$unsafe_client" "$unsafe_server" SEPARATE_LOCAL_SERVER_CONFIG \
  >/dev/null 2>&1; then
  printf '%s\n' 'Script phải từ chối plaintext sync bật.' >&2
  exit 1
fi
unsafe_after=$(shasum -a 256 "$unsafe_client" | awk '{ print $1 }')
if [[ "$unsafe_before" != "$unsafe_after" || -e "$unsafe_server" ]]; then
  printf '%s\n' 'Fail-closed path đã thay đổi file cấu hình.' >&2
  exit 1
fi

printf '%s\n' 'Local env separation contract pass.'
