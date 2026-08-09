#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR=${1:?"Usage: verify_chrome_extension_package.sh <unpacked-dir>"}

if [[ ! -d "$PACKAGE_DIR" || ! -f "$PACKAGE_DIR/manifest.json" ]]; then
  echo "Chrome Extension package thiếu manifest.json ở root." >&2
  exit 2
fi

jq -e '
  .manifest_version == 3 and
  .minimum_chrome_version == "114" and
  .side_panel.default_path == "index.html" and
  .permissions == ["sidePanel"] and
  .host_permissions == ["https://supabase-api.vnpay.dev/*"] and
  (.content_security_policy.extension_pages | contains("script-src '\''self'\'' '\''wasm-unsafe-eval'\''")) and
  (.content_security_policy.extension_pages | contains("object-src '\''self'\''"))
' "$PACKAGE_DIR/manifest.json" >/dev/null

test -f "$PACKAGE_DIR/index.html"
test -f "$PACKAGE_DIR/service_worker.js"
test -f "$PACKAGE_DIR/vault.js"
test -f "$PACKAGE_DIR/main.dart.js"
test -f "$PACKAGE_DIR/assets/FontManifest.json"
test -f "$PACKAGE_DIR/assets/assets/fonts/Roboto-Regular.ttf"
test -f "$PACKAGE_DIR/assets/assets/fonts/Roboto-Medium.ttf"
test -f "$PACKAGE_DIR/assets/assets/fonts/Roboto-Bold.ttf"
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
