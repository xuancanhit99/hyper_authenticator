#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE_ID=${1:-}
ENV_FILE=${2:-}
CONFIRMATION=${3:-}

if [[ -z "$DEVICE_ID" || -z "$ENV_FILE" ||
  "$CONFIRMATION" != '--allow-app-lock-test' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/app_lock_ios_simulator_smoke.sh SIMULATOR_UUID ENV_FILE --allow-app-lock-test' >&2
  printf '%s\n' \
    'Suite thay đổi biometric preference và điều khiển Face ID của iOS Simulator.' >&2
  exit 64
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy public runtime config: %s\n' "$ENV_FILE" >&2
  exit 66
fi

if ! command -v xcrun >/dev/null 2>&1 ||
  ! xcrun simctl list devices available | grep -Fq "($DEVICE_ID)"; then
  printf '%s\n' \
    'Từ chối chạy: harness chỉ hỗ trợ iOS Simulator available.' >&2
  exit 65
fi

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"
printf '%s\n' \
  'Trước khi chạy: Simulator > Features > Face ID > Enrolled phải được bật.'
printf '%s\n' \
  'Theo phase: chọn Matching Face; chọn Non-matching Face rồi Hủy; cuối cùng chọn Matching Face.'
flutter test integration_test/app_lock_biometric_smoke_test.dart \
  -d "$DEVICE_ID" \
  --dart-define-from-file="$ENV_FILE" \
  --dart-define=ALLOW_DEVICE_APP_LOCK_TEST=true
