#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${1:-}
BUILD_ROOT="$ROOT/build/chrome-extension"
UNPACKED_DIR="$BUILD_ROOT/unpacked"
PACKAGE_VERSION=$(awk '$1 == "version:" { print $2; exit }' "$ROOT/pubspec.yaml")

if [[ -z "$PACKAGE_VERSION" ]]; then
  printf '%s\n' 'Không đọc được package version từ pubspec.yaml.' >&2
  exit 65
fi

ZIP_NAME="hyper-authenticator-${PACKAGE_VERSION}-chrome-extension.zip"
ZIP_PATH="$BUILD_ROOT/$ZIP_NAME"

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Không tìm thấy public config: $ENV_FILE" >&2
    exit 2
  fi
  dart run tool/agent/check_release_config.dart "$ENV_FILE"
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$UNPACKED_DIR"

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
rm -f "$UNPACKED_DIR/flutter_service_worker.js"

"$ROOT/scripts/agent/verify_chrome_extension_package.sh" "$UNPACKED_DIR"

(
  cd "$UNPACKED_DIR"
  zip -X -q -r "$ZIP_PATH" .
)
(
  cd "$BUILD_ROOT"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$ZIP_NAME" >"$ZIP_NAME.sha256"
  else
    shasum -a 256 "$ZIP_NAME" >"$ZIP_NAME.sha256"
  fi
)

echo "Unpacked: $UNPACKED_DIR"
echo "ZIP: $ZIP_PATH"
echo "Checksum: $ZIP_PATH.sha256"
