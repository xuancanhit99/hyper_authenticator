#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${1:-}
BUILD_ROOT="$ROOT/build/chrome-extension"
UNPACKED_DIR="$BUILD_ROOT/unpacked"
PACKAGE_VERSION=$(awk '$1 == "version:" { print $2; exit }' "$ROOT/pubspec.yaml")
FONT_FALLBACK_DIR="$ROOT/chrome_extension/font-fallbacks"
FONT_FALLBACK_PATH="notosans/v37/o-0mIpQlx3QUlC5A4PNB6Ryti20_6n1iPHjcz6L1SoM-jCpoiyD9A99Y41P6zHtY.woff2"
FONT_FALLBACK_CONFIG="fontFallbackBaseUrl: 'font-fallbacks/'"

if [[ -z "$PACKAGE_VERSION" ]]; then
  printf '%s\n' 'Không đọc được package version từ pubspec.yaml.' >&2
  exit 65
fi
if [[ ! -s "$FONT_FALLBACK_DIR/$FONT_FALLBACK_PATH" ]] ||
  [[ ! -s "$FONT_FALLBACK_DIR/OFL.txt" ]]; then
  printf '%s\n' 'Thiếu Noto Sans fallback hoặc giấy phép trong Chrome Extension source.' >&2
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

bootstrap="$UNPACKED_DIR/flutter_bootstrap.js"
if ! grep -Fq "canvasKitBaseUrl: 'canvaskit/'" "$bootstrap"; then
  printf '%s\n' 'Flutter bootstrap không có CanvasKit local contract để cấu hình font fallback.' >&2
  exit 1
fi
if ! grep -Fq "$FONT_FALLBACK_CONFIG" "$bootstrap"; then
  perl -0pi -e "s/canvasKitBaseUrl: 'canvaskit\\/'/canvasKitBaseUrl: 'canvaskit\\/', fontFallbackBaseUrl: 'font-fallbacks\\/'/" \
    "$bootstrap"
fi
fallback_config_count=$(awk -v token="$FONT_FALLBACK_CONFIG" '
  {
    rest = $0
    while ((offset = index(rest, token)) > 0) {
      count++
      rest = substr(rest, offset + length(token))
    }
  }
  END { print count + 0 }
' "$bootstrap")
if [[ "$fallback_config_count" != 1 ]]; then
  printf '%s\n' 'Không thể cấu hình local font fallback cho Chrome Extension.' >&2
  exit 1
fi

cp "$ROOT/chrome_extension/manifest.json" "$UNPACKED_DIR/manifest.json"
cp "$ROOT/chrome_extension/service_worker.js" "$UNPACKED_DIR/service_worker.js"
cp "$ROOT/chrome_extension/index.html" "$UNPACKED_DIR/index.html"
cp "$ROOT/chrome_extension/vault.js" "$UNPACKED_DIR/vault.js"
rm -rf "$UNPACKED_DIR/icons"
cp -R "$ROOT/chrome_extension/icons" "$UNPACKED_DIR/icons"
cp -R "$FONT_FALLBACK_DIR" "$UNPACKED_DIR/font-fallbacks"
rm -f "$UNPACKED_DIR/favicon.png"
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
