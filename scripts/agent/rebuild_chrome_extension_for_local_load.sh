#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CONFIG_PATH=${1:-"$ROOT/.env"}

if [[ $# -gt 1 ]]; then
  printf '%s\n' \
    'Cách dùng: scripts/agent/rebuild_chrome_extension_for_local_load.sh [PUBLIC_CONFIG]' >&2
  exit 64
fi
if [[ ! -f "$CONFIG_PATH" || -L "$CONFIG_PATH" ]]; then
  printf '%s\n' \
    'Public config phải là regular file; mặc định dùng .env trong repository.' >&2
  exit 66
fi

cd "$ROOT"
dart run tool/agent/check_release_config.dart --require-cloud "$CONFIG_PATH"
scripts/agent/build_chrome_extension.sh "$CONFIG_PATH"

printf '\n%s\n' \
  '✓ Đã build lại Chrome Extension từ source checkout hiện tại với cloud config.' \
  '✓ Chrome đang Load unpacked không tự rebuild từ source hoặc GitHub Release.' \
  '✓ Mở chrome://extensions và bấm Reload tại Hyper Authenticator.' \
  "✓ Thư mục cần Load unpacked: $ROOT/build/chrome-extension/unpacked"
