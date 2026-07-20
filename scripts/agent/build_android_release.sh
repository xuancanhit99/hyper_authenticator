#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${1:-}
OUTPUT_DIR=${2:-}
CONFIRMATION=${3:-}
EXPECTED_CONFIRMATION=--allow-app-signing
FINGERPRINT_FILE="$ROOT/android/app-signing-certificate.sha256"

usage() {
  printf '%s\n' \
    'Usage: scripts/agent/build_android_release.sh ENV_FILE OUTPUT_DIR --allow-app-signing' >&2
}

if [[ -z "$ENV_FILE" || -z "$OUTPUT_DIR" ||
  "$CONFIRMATION" != "$EXPECTED_CONFIRMATION" ]]; then
  usage
  exit 64
fi
for command in flutter dart awk find grep tr; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu Android release dependency: %s\n' "$command" >&2
    exit 69
  fi
done

cd "$ROOT"
if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Public runtime config không tồn tại: %s\n' "$ENV_FILE" >&2
  exit 66
fi
dart run tool/agent/check_release_config.dart "$ENV_FILE"

if [[ -e "$OUTPUT_DIR" ]] && find "$OUTPUT_DIR" -mindepth 1 -print -quit | grep -q .; then
  printf 'Output directory phải rỗng: %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

expected_fingerprint=$(tr -d ':[:space:]' < "$FINGERPRINT_FILE" | tr '[:upper:]' '[:lower:]')
if [[ ! "$expected_fingerprint" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' 'Fingerprint pin trong repository không hợp lệ.' >&2
  exit 65
fi

flutter build apk --release \
  --dart-define-from-file="$ENV_FILE" \
  --split-debug-info=build/symbols/android

apk_path="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -s "$apk_path" ]]; then
  printf '%s\n' 'Không tìm thấy Android release APK sau build.' >&2
  exit 1
fi

apksigner=${ANDROID_APKSIGNER:-}
if [[ -z "$apksigner" ]]; then
  sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
  if [[ -z "$sdk_root" && -f "$ROOT/android/local.properties" ]]; then
    sdk_root=$(awk -F= '$1 == "sdk.dir" {
      value = substr($0, index($0, "=") + 1)
      print value
      exit
    }' "$ROOT/android/local.properties")
  fi
  if [[ -z "$sdk_root" && -d "$HOME/Library/Android/sdk" ]]; then
    sdk_root="$HOME/Library/Android/sdk"
  fi
  if [[ -n "$sdk_root" && -d "$sdk_root/build-tools" ]]; then
    apksigner=$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 \
      -type f -name apksigner -perm -u+x -print | LC_ALL=C sort | tail -n 1)
  fi
fi
if [[ -z "$apksigner" || ! -x "$apksigner" ]]; then
  printf '%s\n' 'Không tìm thấy apksigner trong Android SDK build-tools.' >&2
  exit 69
fi

verification_output=$($apksigner verify --verbose --print-certs "$apk_path") || {
  printf '%s\n' 'APK signature verification thất bại.' >&2
  exit 1
}
if ! grep -Fxq 'Number of signers: 1' <<<"$verification_output"; then
  printf '%s\n' 'APK phải có đúng một signer.' >&2
  exit 1
fi
actual_fingerprint=$(awk -F': ' \
  '/certificate SHA-256 digest:/{print $NF; exit}' \
  <<<"$verification_output" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
unset verification_output
if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  printf 'APK signer fingerprint mismatch: expected %s, actual %s.\n' \
    "$expected_fingerprint" "${actual_fingerprint:-missing}" >&2
  exit 1
fi

package_version=$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)
artifact_name="hyper-authenticator-${package_version}-android.apk"
cp "$apk_path" "$OUTPUT_DIR/$artifact_name"
if command -v sha256sum >/dev/null 2>&1; then
  hash_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  hash_command=(shasum -a 256)
else
  printf '%s\n' 'Thiếu SHA-256 utility (sha256sum hoặc shasum).' >&2
  exit 69
fi
(
  cd "$OUTPUT_DIR"
  "${hash_command[@]}" "$artifact_name" > "$artifact_name.sha256"
  "${hash_command[@]}" --check "$artifact_name.sha256"
)

printf '✓ Signed Android APK: %s\n' "$OUTPUT_DIR/$artifact_name"
printf '✓ App signing certificate SHA-256: %s\n' "$expected_fingerprint"
