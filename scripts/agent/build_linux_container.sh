#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

REF=${1:-HEAD}
FLUTTER_VERSION=3.44.6
UBUNTU_IMAGE='ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Docker daemon là bắt buộc cho Linux isolated compile.' >&2
  exit 69
fi

if ! git cat-file -e "$REF^{commit}" 2>/dev/null; then
  printf '%s\n' "Git ref không hợp lệ: $REF" >&2
  exit 64
fi

if [[ -n "$(git status --short)" ]]; then
  printf '%s\n' \
    "Lưu ý: chỉ build committed ref $REF; working-tree changes không được đưa vào container."
fi

# Git archive loại .env, ignored file, Git metadata và working-tree change. Docker
# container tự hủy sau compile nên không tạo artifact root-owned trên host.
git archive --format=tar "$REF" |
  docker run --rm --interactive "$UBUNTU_IMAGE" bash -lc "set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates git curl unzip xz-utils zip \\
  clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev \\
  libjsoncpp-dev liblzma-dev >/dev/null
git clone --quiet --depth 1 --branch '$FLUTTER_VERSION' \\
  https://github.com/flutter/flutter.git /opt/flutter
export PATH=/opt/flutter/bin:\$PATH
flutter config --no-analytics --enable-linux-desktop >/dev/null
flutter precache --linux >/dev/null
mkdir -p /workspace
tar -xf - -C /workspace
cd /workspace
flutter pub get
flutter build linux --release
test -x build/linux/arm64/release/bundle/hyper_authenticator || \\
  test -x build/linux/x64/release/bundle/hyper_authenticator
printf '%s\\n' 'Linux release compile pass: Flutter $FLUTTER_VERSION, Ubuntu 24.04.'"
