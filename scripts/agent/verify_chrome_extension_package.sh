#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR=${1:?"Usage: verify_chrome_extension_package.sh <unpacked-dir>"}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SOURCE_FALLBACK_LOCK="$ROOT/chrome_extension/font-fallbacks/sources.lock"
EXPECTED_FALLBACK_ENTRIES=868
EXPECTED_FALLBACK_FONTS=724
EXPECTED_FALLBACK_LICENSES=144

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ ! -d "$PACKAGE_DIR" || ! -f "$PACKAGE_DIR/manifest.json" ]]; then
  echo "Chrome Extension package thiếu manifest.json ở root." >&2
  exit 2
fi

# ZIP được tạo trên Linux có thể chứa hai path chỉ khác hoa/thường. Khi người
# dùng giải nén trên macOS/Windows mặc định, một trong hai file sẽ bị ghi đè.
# Từ chối package đó trước khi kiểm tra contract còn lại.
case_collisions=$( (
  cd "$PACKAGE_DIR"
  find . -mindepth 1 -print | LC_ALL=C awk '
    {
      path = tolower($0)
      if (seen[path]++) print $0
    }
  '
) )
if [[ -n "$case_collisions" ]]; then
  printf '%s\n%s\n' \
    'Chrome Extension package chứa path xung đột trên filesystem không phân biệt hoa/thường:' \
    "$case_collisions" >&2
  exit 1
fi

jq -e '
  .manifest_version == 3 and
  .minimum_chrome_version == "114" and
  .side_panel.default_path == "index.html" and
  .permissions == ["sidePanel", "identity"] and
  .host_permissions == ["https://supabase-api.vnpay.dev/*"] and
  .action.default_icon == {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png"
  } and
  .icons == {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  } and
  (.content_security_policy.extension_pages | contains("script-src '\''self'\'' '\''wasm-unsafe-eval'\''")) and
  (.content_security_policy.extension_pages | contains("object-src '\''self'\''"))
' "$PACKAGE_DIR/manifest.json" >/dev/null

test -f "$PACKAGE_DIR/index.html"
test -f "$PACKAGE_DIR/service_worker.js"
test -f "$PACKAGE_DIR/vault.js"
test -f "$PACKAGE_DIR/oauth.js"
test -f "$PACKAGE_DIR/main.dart.js"
test -f "$PACKAGE_DIR/flutter_bootstrap.js"
test -f "$PACKAGE_DIR/assets/FontManifest.json"
test -f "$PACKAGE_DIR/assets/assets/fonts/Roboto-Regular.ttf"
test -f "$PACKAGE_DIR/assets/assets/fonts/Roboto-Medium.ttf"
test -f "$PACKAGE_DIR/assets/assets/fonts/Roboto-Bold.ttf"
fallback_root="$PACKAGE_DIR/font-fallbacks"
fallback_lock="$fallback_root/sources.lock"
if [[ ! -s "$SOURCE_FALLBACK_LOCK" ]] ||
  [[ ! -s "$fallback_lock" ]] ||
  ! cmp -s "$SOURCE_FALLBACK_LOCK" "$fallback_lock"; then
  echo 'Chrome Extension font fallback lock thiếu hoặc không khớp source pin.' >&2
  exit 1
fi

fallback_entries=$(awk -F '\t' 'NF { count++ } END { print count + 0 }' "$fallback_lock")
fallback_fonts=$(awk -F '\t' '$3 ~ /\.woff2$/ { count++ } END { print count + 0 }' "$fallback_lock")
fallback_licenses=$(awk -F '\t' '$3 ~ /^licenses\/[a-z0-9]+\/OFL\.txt$/ { count++ } END { print count + 0 }' "$fallback_lock")
if [[ "$fallback_entries" != "$EXPECTED_FALLBACK_ENTRIES" ]] ||
  [[ "$fallback_fonts" != "$EXPECTED_FALLBACK_FONTS" ]] ||
  [[ "$fallback_licenses" != "$EXPECTED_FALLBACK_LICENSES" ]]; then
  echo 'Chrome Extension font fallback inventory không đầy đủ.' >&2
  exit 1
fi

expected_fallback_paths=$(mktemp "${TMPDIR:-/tmp}/hyper-fallback-expected.XXXXXX")
actual_fallback_paths=$(mktemp "${TMPDIR:-/tmp}/hyper-fallback-actual.XXXXXX")
trap 'rm -f "$expected_fallback_paths" "$actual_fallback_paths"' EXIT
{
  printf '%s\n' 'sources.lock'
  cut -f3 "$fallback_lock"
} | LC_ALL=C sort >"$expected_fallback_paths"
(
  cd "$fallback_root"
  find . -type f -print | sed 's#^\./##' | LC_ALL=C sort
) >"$actual_fallback_paths"
if ! cmp -s "$expected_fallback_paths" "$actual_fallback_paths"; then
  echo 'Chrome Extension font fallback package thiếu hoặc thừa file.' >&2
  exit 1
fi

while IFS=$'\t' read -r expected_sha _ relative_path; do
  fallback_file="$fallback_root/$relative_path"
  if [[ ! -s "$fallback_file" ]] ||
    [[ $(sha256_file "$fallback_file") != "$expected_sha" ]]; then
    printf 'Chrome Extension font fallback sai checksum: %s\n' "$relative_path" >&2
    exit 1
  fi
  if [[ "$relative_path" == *.woff2 ]]; then
    file "$fallback_file" | grep -Fq 'Web Open Font Format (Version 2)' || {
      printf 'Chrome Extension fallback không phải WOFF2: %s\n' "$relative_path" >&2
      exit 1
    }
  else
    grep -Fq 'SIL Open Font License' "$fallback_file" || {
      printf 'Chrome Extension fallback thiếu OFL: %s\n' "$relative_path" >&2
      exit 1
    }
  fi
done <"$fallback_lock"

test -s "$fallback_root/notosanshk/v32/nKKF-GM_FYFRJvXzVXaAPe97P1KHynJFP716qHB--oD7kYrUzT7-NvA3pTohjc3XVtNXX8A7gG1LO2KAPAw.119.woff2" || {
  echo 'Chrome Extension thiếu regression font Noto Sans HK 104.' >&2
  exit 1
}
for icon_size in 16 32 48 128; do
  icon="$PACKAGE_DIR/icons/icon-$icon_size.png"
  test -f "$icon"
  file "$icon" | grep -Eq "PNG image data, ${icon_size} x ${icon_size},"
done
test -f "$PACKAGE_DIR/canvaskit/canvaskit.js"
test -f "$PACKAGE_DIR/canvaskit/canvaskit.wasm"

jq -e '
  any(.[]; .family == "Roboto" and
    ([.fonts[].asset] | sort) == [
      "assets/fonts/Roboto-Bold.ttf",
      "assets/fonts/Roboto-Medium.ttf",
      "assets/fonts/Roboto-Regular.ttf"
    ])
' "$PACKAGE_DIR/assets/FontManifest.json" >/dev/null || {
  echo "Chrome Extension thiếu Roboto đã bundle trong FontManifest." >&2
  exit 1
}

fallback_config="fontFallbackBaseUrl: 'font-fallbacks/'"
fallback_config_count=$(awk -v token="$fallback_config" '
  {
    rest = $0
    while ((offset = index(rest, token)) > 0) {
      count++
      rest = substr(rest, offset + length(token))
    }
  }
  END { print count + 0 }
' "$PACKAGE_DIR/flutter_bootstrap.js")
if [[ "$fallback_config_count" != 1 ]]; then
  echo 'Chrome Extension bootstrap không ép CanvasKit dùng font fallback local.' >&2
  exit 1
fi

if [[ -e "$PACKAGE_DIR/flutter_service_worker.js" ]]; then
  echo "MV3 package không được chứa Flutter PWA service worker." >&2
  exit 1
fi

if find "$PACKAGE_DIR" -type f \( -name '*.map' -o -name '*.debug' -o -name '*.pdb' \) \
  -print -quit | grep -q .; then
  echo "Chrome Extension package không được chứa source-map/debug artifact." >&2
  exit 1
fi

if find "$PACKAGE_DIR" -type f \( -name '*.js' -o -name '*.mjs' \) \
  -exec grep -a -n -E \
    'https?://[[:alnum:]./_?&=:%#@+,-]+\.(js|wasm)([?#][[:alnum:]./_?&=:%#@+,-]*)?' {} +; then
  echo "Phát hiện executable code tải từ xa trong Chrome Extension package." >&2
  exit 1
fi

if find "$PACKAGE_DIR" -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.html' \) \
  -exec grep -a -n -E 'zxing-wasm|importScripts\(|<script[^>]+https?://' {} +; then
  echo "Phát hiện scanner CDN hoặc remote script trong Chrome Extension package." >&2
  exit 1
fi

if ! grep -Fq 'generateKey(' "$PACKAGE_DIR/vault.js" ||
  ! grep -Fq 'false,' "$PACKAGE_DIR/vault.js" ||
  ! grep -Fq 'AES-GCM' "$PACKAGE_DIR/vault.js"; then
  echo "Chrome Extension vault không có contract WebCrypto AES-GCM key non-extractable." >&2
  exit 1
fi

echo "Chrome Extension package contract pass: $PACKAGE_DIR"
