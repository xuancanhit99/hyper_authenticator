#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

TARGET=${1:-host}
ENV_FILE=${2:-}

if [[ $# -gt 2 ]]; then
  printf 'Usage: %s [host|android|ios|web|macos|linux|windows] [env-file]\n' \
    "$0" >&2
  exit 64
fi

define_arg=
if [[ -n "$ENV_FILE" ]]; then
  dart run tool/agent/check_release_config.dart "$ENV_FILE"
  define_arg="--dart-define-from-file=$ENV_FILE"
fi

flutter_build() {
  if [[ -n "$define_arg" ]]; then
    flutter build "$@" "$define_arg"
  else
    flutter build "$@"
  fi
}

build_macos() {
  if security find-identity -v -p codesigning 2>/dev/null |
      grep -Eq '[1-9][0-9]* valid identities found'; then
    flutter_build macos --debug
    return
  fi

  printf '%s\n' \
    'Không có Apple signing identity; chỉ compile macOS unsigned, không runtime.'
  flutter_build macos --debug --config-only

  # Xcode exports its environment in verbose build output. Use an allowlisted
  # environment and quiet mode so CI/operator credentials cannot enter logs.
  env -i \
    HOME="$HOME" \
    USER="${USER:-builder}" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="${TMPDIR:-/tmp}" \
    DEVELOPER_DIR="$(xcode-select -p)" \
    /usr/bin/xcodebuild -quiet \
      -workspace macos/Runner.xcworkspace \
      -scheme Runner \
      -configuration Debug \
      -derivedDataPath build/macos \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY= \
      build
  printf '%s\n' \
    '✓ Compiled unsigned build/macos/Build/Products/Debug/Hyper Authenticator.app'
}

build_target() {
  case "$1" in
    android)
      flutter_build apk --debug
      ;;
    ios)
      flutter_build ios --simulator --debug
      ;;
    web)
      flutter_build web --release --no-web-resources-cdn
      ;;
    macos)
      build_macos
      ;;
    linux)
      flutter_build linux --release
      ;;
    windows)
      flutter_build windows --release
      ;;
    *)
      printf 'Target không hợp lệ: %s\n' "$1" >&2
      exit 64
      ;;
  esac
}

flutter pub get

if [[ "$TARGET" != host ]]; then
  build_target "$TARGET"
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    build_target android
    build_target web
    build_target macos
    ;;
  Linux)
    build_target android
    build_target web
    build_target linux
    ;;
  *)
    build_target windows
    ;;
esac
