#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/agent/separate_local_env.sh"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-env-test.XXXXXX")
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

read_file_mode() {
  local path=$1
  local candidate

  if candidate=$(stat -f '%Lp' "$path" 2>/dev/null) &&
    [[ "$candidate" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if candidate=$(stat -c '%a' "$path" 2>/dev/null) &&
    [[ "$candidate" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

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
if [[ $(read_file_mode "$client_env") != 600 ||
  $(read_file_mode "$server_env") != 600 ]]; then
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

printf '%s\n' 'Local env separation contract pass.'
