#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

TARGET=${1:-host}

build_target() {
  case "$1" in
    android)
      flutter build apk --debug
      ;;
    ios)
      flutter build ios --simulator --debug
      ;;
    web)
      flutter build web --release
      ;;
    macos)
      flutter build macos --debug
      ;;
    linux)
      flutter build linux --release
      ;;
    windows)
      flutter build windows --release
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
