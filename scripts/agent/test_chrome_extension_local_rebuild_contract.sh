#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WRAPPER="$ROOT/scripts/agent/rebuild_chrome_extension_for_local_load.sh"
VALIDATOR="$ROOT/tool/agent/check_release_config.dart"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hyper-chrome-local-rebuild.XXXXXX")

cleanup() {
  find "$WORK_DIR" -depth -delete
}
trap cleanup EXIT INT TERM

bash -n "$WRAPPER"

cloud_config="$WORK_DIR/cloud.json"
local_only_config="$WORK_DIR/local-only.json"
cat >"$cloud_config" <<'EOF'
{
  "SUPABASE_URL": "https://api.example.com",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_0123456789012345678901_01234567",
  "PASSWORD_RECOVERY_URL": "https://auth.example.com/reset-password/"
}
EOF
printf '%s\n' '{}' >"$local_only_config"

dart run "$VALIDATOR" --require-cloud "$cloud_config" >/dev/null
if dart run "$VALIDATOR" --require-cloud "$local_only_config" \
  >/dev/null 2>&1; then
  printf '%s\n' \
    'Local-load wrapper không được chấp nhận config local-only.' >&2
  exit 1
fi

for contract in \
  'check_release_config.dart --require-cloud' \
  'build_chrome_extension.sh "$CONFIG_PATH"' \
  'chrome://extensions' \
  'build/chrome-extension/unpacked'; do
  if ! grep -Fq "$contract" "$WRAPPER"; then
    printf 'Local-load wrapper thiếu contract: %s\n' "$contract" >&2
    exit 1
  fi
done

printf '%s\n' 'Chrome Extension local rebuild contract pass.'
