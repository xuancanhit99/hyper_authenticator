#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${1:-}
BUILD_ROOT="$ROOT/build/chrome-extension"
UNPACKED_DIR="$BUILD_ROOT/unpacked"

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Không tìm thấy public config: $ENV_FILE" >&2
    exit 2
  fi
  dart run tool/agent/check_release_config.dart "$ENV_FILE"
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$UNPACKED_DIR/icons"

BUILD_ARGS=(
  --release
  --target lib/main_extension.dart
  --output "$UNPACKED_DIR"
  --dart-define=HYPER_CHROME_EXTENSION=true
)
if [[ -n "$ENV_FILE" ]]; then
  BUILD_ARGS+=("--dart-define-from-file=$ENV_FILE")
fi

flutter build web "${BUILD_ARGS[@]}"

cp "$ROOT/chrome_extension/manifest.json" "$UNPACKED_DIR/manifest.json"
cp "$ROOT/chrome_extension/service_worker.js" "$UNPACKED_DIR/service_worker.js"
cp "$ROOT/chrome_extension/index.html" "$UNPACKED_DIR/index.html"
cp "$ROOT/chrome_extension/vault.js" "$UNPACKED_DIR/vault.js"
cp "$ROOT/web/icons/Icon-192.png" "$UNPACKED_DIR/icons/icon-192.png"
rm -f "$UNPACKED_DIR/flutter_service_worker.js"

"$ROOT/scripts/agent/verify_chrome_extension_package.sh" "$UNPACKED_DIR"

(
  cd "$UNPACKED_DIR"
  zip -X -q -r "$BUILD_ROOT/hyper-authenticator-chrome-extension.zip" .
)

echo "Unpacked: $UNPACKED_DIR"
echo "ZIP: $BUILD_ROOT/hyper-authenticator-chrome-extension.zip"
