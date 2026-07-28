#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE_ID=${1:-}
ENV_FILE=${2:-}
PHASE=${3:-}
CONFIRMATION=${4:-}

if [[ -z "$DEVICE_ID" || -z "$ENV_FILE" ||
  ("$PHASE" != export && "$PHASE" != restore) ||
  "$CONFIRMATION" != '--allow-test-vault-reset' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/encrypted_backup_device_smoke.sh DEVICE_ID ENV_FILE export|restore --allow-test-vault-reset' >&2
  printf '%s\n' \
    'CẢNH BÁO: suite thay toàn bộ local vault trên target và cần operator điều khiển system sheet.' >&2
  exit 64
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf '%s\n' 'Không tìm thấy public runtime config.' >&2
  exit 66
fi

IS_VIRTUAL_DEVICE=false
if [[ "$DEVICE_ID" == emulator-* ]]; then
  IS_VIRTUAL_DEVICE=true
elif command -v xcrun >/dev/null 2>&1 &&
  xcrun simctl list devices available |
    grep -Fq "($DEVICE_ID)"; then
  IS_VIRTUAL_DEVICE=true
fi

if [[ "$IS_VIRTUAL_DEVICE" != true ]]; then
  printf '%s\n' \
    'Từ chối chạy: encrypted-backup smoke chỉ hỗ trợ Android emulator hoặc iOS Simulator.' >&2
  printf '%s\n' \
    'Không chạy trên thiết bị thật hoặc macOS vì suite thay toàn bộ local vault.' >&2
  exit 65
fi

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"
flutter test integration_test/encrypted_backup_runtime_smoke_test.dart \
  -d "$DEVICE_ID" \
  --dart-define-from-file="$ENV_FILE" \
  --dart-define=ALLOW_DEVICE_TEST_VAULT_RESET=true \
  --dart-define=ENCRYPTED_BACKUP_SMOKE_PHASE="$PHASE"
