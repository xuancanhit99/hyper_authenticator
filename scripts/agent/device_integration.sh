#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE_ID=${1:-}
ENV_FILE=${2:-}
CONFIRMATION=${3:-}

if [[ -z "$DEVICE_ID" || -z "$ENV_FILE" ||
  "$CONFIRMATION" != '--allow-test-vault-reset' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/device_integration.sh DEVICE_ID ENV_FILE --allow-test-vault-reset' >&2
  printf '%s\n' \
    'CẢNH BÁO: suite thay toàn bộ local vault trên target bằng fixture rồi xóa fixture.' >&2
  exit 64
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy public runtime config: %s\n' "$ENV_FILE" >&2
  exit 66
fi

IS_VIRTUAL_DEVICE=false
if [[ "$DEVICE_ID" == emulator-* ]]; then
  IS_VIRTUAL_DEVICE=true
elif command -v xcrun >/dev/null 2>&1 &&
  xcrun simctl list devices available | grep -Fq "($DEVICE_ID)"; then
  IS_VIRTUAL_DEVICE=true
fi

if [[ "$IS_VIRTUAL_DEVICE" != true ]]; then
  printf '%s\n' \
    'Từ chối chạy: harness chỉ hỗ trợ Android emulator hoặc iOS Simulator.' >&2
  printf '%s\n' \
    'Không chạy trên máy thật hoặc macOS vì suite thay toàn bộ local vault.' >&2
  exit 65
fi

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"
flutter test integration_test/local_vault_smoke_test.dart \
  -d "$DEVICE_ID" \
  --dart-define-from-file="$ENV_FILE" \
  --dart-define=ALLOW_DEVICE_TEST_VAULT_RESET=true
