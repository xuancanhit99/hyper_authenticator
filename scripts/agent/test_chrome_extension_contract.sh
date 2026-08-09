#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MANIFEST="$ROOT/chrome_extension/manifest.json"
BUILDER="$ROOT/scripts/agent/build_chrome_extension.sh"
VERIFIER="$ROOT/scripts/agent/verify_chrome_extension_package.sh"

bash -n "$BUILDER" "$VERIFIER"
jq -e '
  .manifest_version == 3 and
  .minimum_chrome_version == "114" and
  .side_panel.default_path == "index.html" and
  .permissions == ["sidePanel"] and
  .host_permissions == ["https://supabase-api.vnpay.dev/*"]
' "$MANIFEST" >/dev/null

if rg -n 'content_scripts|activeTab|"tabs"|"scripting"|<all_urls>|chrome\.storage' \
  "$MANIFEST" "$ROOT/chrome_extension/service_worker.js" "$ROOT/chrome_extension/vault.js"; then
  echo "Chrome Extension MVP xin capability ngoài contract tối giản." >&2
  exit 1
fi

if ! rg -q 'HYPER_CHROME_EXTENSION=true' "$BUILDER" ||
  ! rg -q 'vault.js' "$BUILDER" ||
  ! rg -q 'main_extension.dart' "$BUILDER" ||
  ! rg -q 'ZIP_NAME.sha256' "$BUILDER"; then
  echo "Chrome Extension builder không có entrypoint/vault contract." >&2
  exit 1
fi

if ! rg -q 'extractable=false' "$ROOT/docs/adr/0022-chrome-extension-side-panel-vault.md" ||
  ! rg -q "false," "$ROOT/chrome_extension/vault.js"; then
  echo "Chrome Extension vault không giữ contract key non-extractable." >&2
  exit 1
fi

for font in Roboto-Regular.ttf Roboto-Medium.ttf Roboto-Bold.ttf; do
  test -f "$ROOT/assets/fonts/$font" || {
    echo "Chrome Extension thiếu font local $font." >&2
    exit 1
  }
done

if ! rg -q 'family: Roboto' "$ROOT/pubspec.yaml" ||
  ! rg -q 'assets/fonts/Roboto-Regular.ttf' "$ROOT/pubspec.yaml"; then
  echo "Chrome Extension không khai báo font Roboto local." >&2
  exit 1
fi

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-chrome-extension-contract.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT
cp "$MANIFEST" "$temporary_dir/manifest.json"
if "$VERIFIER" "$temporary_dir" >/dev/null 2>&1; then
  echo "Chrome Extension verifier không fail closed với package thiếu file." >&2
  exit 1
fi

case_collision_dir="$temporary_dir/case-collision"
mkdir -p "$case_collision_dir/icons"
cp "$MANIFEST" "$case_collision_dir/manifest.json"
touch "$case_collision_dir/icons/Icon-192.png" \
  "$case_collision_dir/icons/icon-192.png"
if [[ $(find "$case_collision_dir/icons" -type f | wc -l | tr -d ' ') -eq 2 ]]; then
  if "$VERIFIER" "$case_collision_dir" > /dev/null \
    2>"$temporary_dir/case-collision.stderr"; then
    echo "Chrome Extension verifier không fail closed với path case collision." >&2
    exit 1
  fi
  if ! rg -q 'xung đột.*hoa/thường' "$temporary_dir/case-collision.stderr"; then
    echo "Chrome Extension verifier fail sai lý do với path case collision." >&2
    exit 1
  fi
elif ! rg -q 'tolower\(\$0\)' "$VERIFIER"; then
  echo "Chrome Extension verifier thiếu case-collision guard." >&2
  exit 1
fi

printf '%s\n' '✓ Chrome Extension static contract harness pass'
