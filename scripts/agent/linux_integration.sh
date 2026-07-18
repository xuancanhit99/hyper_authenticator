#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${1:-}
CONFIRMATION=${2:-}

if [[ -z "$ENV_FILE" ||
  "$CONFIRMATION" != '--allow-test-vault-reset' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/linux_integration.sh ENV_FILE --allow-test-vault-reset' >&2
  printf '%s\n' \
    'CẢNH BÁO: suite thay local vault trong Linux sandbox rồi xóa sandbox.' >&2
  exit 64
fi

if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'Từ chối chạy: harness này chỉ hỗ trợ Linux.' >&2
  exit 65
fi

if [[ ${CI:-} != true ]]; then
  printf '%s\n' \
    'Từ chối chạy ngoài CI: harness chỉ dành cho Linux runner tách biệt.' >&2
  exit 65
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy public runtime config: %s\n' "$ENV_FILE" >&2
  exit 66
fi

for command in dbus-run-session gnome-keyring-daemon secret-tool xvfb-run; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu Linux integration dependency: %s\n' "$command" >&2
    exit 69
  fi
done

ENV_FILE=$(realpath "$ENV_FILE")
SANDBOX=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-linux.XXXXXX")
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

export HYPER_AUTH_TEST_ROOT="$ROOT"
export HYPER_AUTH_TEST_ENV_FILE="$ENV_FILE"
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_CACHE_HOME="$SANDBOX/cache"
export XDG_RUNTIME_DIR="$SANDBOX/runtime"

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"

dbus-run-session -- bash <<'SESSION'
set -euo pipefail

eval "$(printf '\n' | gnome-keyring-daemon --unlock 2>/dev/null)"
eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)"

probe_attribute='hyper-authenticator-linux-integration'
clear_probe() {
  secret-tool clear purpose "$probe_attribute" >/dev/null 2>&1 || true
}
trap clear_probe EXIT

printf 'test-only' | secret-tool store \
  --label='Hyper Authenticator CI probe' \
  purpose "$probe_attribute"
if [[ $(secret-tool lookup purpose "$probe_attribute") != 'test-only' ]]; then
  printf '%s\n' 'Private Linux Secret Service probe thất bại.' >&2
  exit 1
fi
clear_probe

cd "$HYPER_AUTH_TEST_ROOT"
xvfb-run --auto-servernum --server-args='-screen 0 1280x1024x24' \
  flutter test integration_test/local_vault_smoke_test.dart \
  --device-id linux \
  --dart-define-from-file="$HYPER_AUTH_TEST_ENV_FILE" \
  --dart-define=ALLOW_DEVICE_TEST_VAULT_RESET=true
SESSION

printf '%s\n' \
  'Linux local-vault integration pass: private keyring, UI, lifecycle và cleanup.'
