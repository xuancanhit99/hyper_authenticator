#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${1:-}
CONFIRMATION=${2:-}

if [[ -z "$ENV_FILE" ||
  "$CONFIRMATION" != '--allow-isolated-remote-user' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/linux_e2ee_integration.sh PUBLIC_CONFIG_JSON --allow-isolated-remote-user' >&2
  printf '%s\n' \
    'CẢNH BÁO: suite ghi encrypted vault của isolated Supabase test user.' >&2
  exit 64
fi

if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'Từ chối chạy: harness này chỉ hỗ trợ Linux.' >&2
  exit 65
fi

if [[ ${CI:-} != true ]]; then
  printf '%s\n' \
    'Từ chối chạy ngoài CI/container: remote mutation cần runner tách biệt.' >&2
  exit 65
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy public runtime config: %s\n' "$ENV_FILE" >&2
  exit 66
fi

for command in dbus-run-session gnome-keyring-daemon jq secret-tool xvfb-run; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu Linux E2EE integration dependency: %s\n' "$command" >&2
    exit 69
  fi
done

if [[ -n ${SUPABASE_SERVICE_ROLE_KEY:-} || -n ${SERVICE_ROLE_KEY:-} ]]; then
  printf '%s\n' \
    'Từ chối chạy: service-role key không được đi vào client integration harness.' >&2
  exit 78
fi

if [[ -z ${E2EE_TEST_EMAIL:-} || -z ${E2EE_TEST_PASSWORD:-} ]]; then
  printf '%s\n' \
    'Thiếu credential của isolated E2EE test user.' >&2
  exit 78
fi

ENV_FILE=$(realpath "$ENV_FILE")
cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"

if ! jq -e '
  type == "object" and
  (has("SERVICE_ROLE_KEY") | not) and
  (has("SUPABASE_SERVICE_ROLE_KEY") | not)
' "$ENV_FILE" >/dev/null; then
  printf '%s\n' \
    'E2EE harness chỉ nhận JSON public config, tuyệt đối không nhận service-role key.' >&2
  exit 78
fi

SANDBOX=$(mktemp -d \
  "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-linux-e2ee.XXXXXX")
test_config="$SANDBOX/client-test-config.json"
cleanup() {
  find "$SANDBOX" -depth -delete
}
trap cleanup EXIT

mkdir -p \
  "$SANDBOX/config" \
  "$SANDBOX/data" \
  "$SANDBOX/cache" \
  "$SANDBOX/runtime"
chmod 0700 "$SANDBOX" "$SANDBOX"/*

# Credential test chỉ đi vào file 0600 của sandbox. Gỡ exported environment
# trước khi khởi chạy Flutter để child process không kế thừa trực tiếp.
test_email=$E2EE_TEST_EMAIL
test_password=$E2EE_TEST_PASSWORD
unset E2EE_TEST_EMAIL E2EE_TEST_PASSWORD

umask 077
jq \
  --arg email "$test_email" \
  --arg password "$test_password" \
  '. + {
    ALLOW_E2EE_REMOTE_TEST_MUTATION: true,
    E2EE_TEST_EMAIL: $email,
    E2EE_TEST_PASSWORD: $password
  }' "$ENV_FILE" >"$test_config"
chmod 0600 "$test_config"
test_email=
test_password=

export HYPER_AUTH_TEST_ROOT="$ROOT"
export HYPER_AUTH_E2EE_TEST_CONFIG="$test_config"
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_CACHE_HOME="$SANDBOX/cache"
export XDG_RUNTIME_DIR="$SANDBOX/runtime"

dbus-run-session -- bash <<'SESSION'
set -euo pipefail

if [[ -n ${SUPABASE_SERVICE_ROLE_KEY:-} || -n ${SERVICE_ROLE_KEY:-} ||
  -n ${E2EE_TEST_EMAIL:-} || -n ${E2EE_TEST_PASSWORD:-} ]]; then
  printf '%s\n' 'Credential bị kế thừa trực tiếp vào client process.' >&2
  exit 1
fi

eval "$(printf '\n' | gnome-keyring-daemon --unlock 2>/dev/null)"
eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)"

probe_attribute='hyper-authenticator-linux-e2ee-integration'
clear_probe() {
  secret-tool clear purpose "$probe_attribute" >/dev/null 2>&1 || true
}
trap clear_probe EXIT

printf 'test-only' | secret-tool store \
  --label='Hyper Authenticator E2EE CI probe' \
  purpose "$probe_attribute"
if [[ $(secret-tool lookup purpose "$probe_attribute") != 'test-only' ]]; then
  printf '%s\n' 'Private Linux Secret Service probe thất bại.' >&2
  exit 1
fi
clear_probe

cd "$HYPER_AUTH_TEST_ROOT"
xvfb-run --auto-servernum --server-args='-screen 0 1280x1024x24' \
  flutter test integration_test/encrypted_sync_smoke_test.dart \
  --device-id linux \
  --dart-define-from-file="$HYPER_AUTH_E2EE_TEST_CONFIG"
SESSION

printf '%s\n' \
  'Linux authenticated E2EE integration pass: setup, sync, recovery và key rotation.'
