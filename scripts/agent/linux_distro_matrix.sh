#!/usr/bin/env bash
set -euo pipefail

PACKAGE=${1:-}
CONFIRMATION=${2:-}

if [[ -z "$PACKAGE" ||
  "$CONFIRMATION" != '--allow-container-package-install' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/linux_distro_matrix.sh PACKAGE_DEB --allow-container-package-install' >&2
  exit 64
fi

if [[ $(uname -s) != Linux ||
  ${CI:-} != true ||
  ${GITHUB_ACTIONS:-} != true ||
  ${RUNNER_ENVIRONMENT:-} != github-hosted ||
  ${RUNNER_OS:-} != Linux ]]; then
  printf '%s\n' \
    'Từ chối chạy: distro matrix chỉ dành cho GitHub-hosted Linux runner tạm.' >&2
  exit 65
fi

if [[ ! -f "$PACKAGE" ]]; then
  printf 'Không tìm thấy Debian package: %s\n' "$PACKAGE" >&2
  exit 66
fi

if ! command -v docker >/dev/null 2>&1 ||
  ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Docker daemon là bắt buộc cho Linux distro matrix.' >&2
  exit 69
fi

PACKAGE=$(realpath "$PACKAGE")
MATRIX=(
  'ubuntu-22.04|ubuntu@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982'
  'ubuntu-24.04|ubuntu@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'
  'debian-12|debian@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818'
  'debian-13|debian@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd'
)

for entry in "${MATRIX[@]}"; do
  label=${entry%%|*}
  image=${entry#*|}
  printf '== Linux distro runtime: %s ==\n' "$label"

  docker run --rm --interactive \
    --mount "type=bind,src=$PACKAGE,dst=/package/app.deb,readonly" \
    --env "HYPER_AUTH_DISTRO_LABEL=$label" \
    "$image" bash -s <<'CONTAINER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
  dbus-x11 desktop-file-utils libgl1-mesa-dri \
  libsecret-tools xauth xvfb /package/app.deb >/dev/null

test -x /usr/bin/hyper-authenticator
test -f /usr/share/applications/app.hyperz.authenticator.desktop
desktop-file-validate /usr/share/applications/app.hyperz.authenticator.desktop
for runtime_package in gnome-keyring libegl1 libgles2 libgl1; do
  if [[ $(dpkg-query -W -f='${Status}' "$runtime_package") != \
    'install ok installed' ]]; then
    printf 'Package thiếu runtime dependency: %s\n' "$runtime_package" >&2
    exit 1
  fi
done
if ldd /opt/hyper-authenticator/hyper_authenticator |
  grep -F 'not found' >/dev/null; then
  printf '%s\n' 'Installed executable còn thiếu shared library.' >&2
  exit 1
fi

runtime=$(mktemp -d)
chmod 0700 "$runtime"
export XDG_CONFIG_HOME="$runtime/config"
export XDG_DATA_HOME="$runtime/data"
export XDG_CACHE_HOME="$runtime/cache"
export XDG_RUNTIME_DIR="$runtime/run"
mkdir -p \
  "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 0700 "$runtime"/*
cleanup() {
  find "$runtime" -depth -delete
}
trap cleanup EXIT

dbus-run-session -- bash <<'SESSION'
set -euo pipefail

eval "$(printf '\n' | gnome-keyring-daemon --unlock 2>/dev/null)"
eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)"

probe_attribute="hyper-auth-distro-${HYPER_AUTH_DISTRO_LABEL}"
clear_probe() {
  secret-tool clear purpose "$probe_attribute" >/dev/null 2>&1 || true
}
weston_pid=''
cleanup_session() {
  clear_probe
  if [[ -n "$weston_pid" ]]; then
    kill "$weston_pid" >/dev/null 2>&1 || true
    wait "$weston_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup_session EXIT

printf 'test-only' | secret-tool store \
  --label='Hyper Authenticator distro probe' \
  purpose "$probe_attribute"
if [[ $(secret-tool lookup purpose "$probe_attribute") != 'test-only' ]]; then
  printf '%s\n' 'Private Secret Service probe thất bại.' >&2
  exit 1
fi
clear_probe

set +e
xvfb-run --auto-servernum --server-args='-screen 0 1280x1024x24' \
  timeout --signal=TERM 8s /usr/bin/hyper-authenticator \
  >"$XDG_RUNTIME_DIR/app.log" 2>&1
exit_code=$?
set -e
if [[ $exit_code -ne 124 ]]; then
  sed -n '1,120p' "$XDG_RUNTIME_DIR/app.log" >&2
  printf 'Installed app thoát sớm với code %s.\n' "$exit_code" >&2
  exit 1
fi

apt-get install -y -qq weston >/dev/null
weston --backend=headless-backend.so \
  --socket=wayland-1 --idle-time=0 \
  --log="$XDG_RUNTIME_DIR/weston.log" &
weston_pid=$!
for _ in $(seq 1 50); do
  [[ -S "$XDG_RUNTIME_DIR/wayland-1" ]] && break
  sleep 0.1
done
if [[ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]]; then
  cat "$XDG_RUNTIME_DIR/weston.log" >&2
  printf '%s\n' 'Weston headless không tạo Wayland socket.' >&2
  exit 1
fi

set +e
GDK_BACKEND=wayland WAYLAND_DISPLAY=wayland-1 \
  timeout --signal=TERM 8s /usr/bin/hyper-authenticator \
  >"$XDG_RUNTIME_DIR/app-wayland.log" 2>&1
exit_code=$?
set -e
if [[ $exit_code -ne 124 ]]; then
  cat "$XDG_RUNTIME_DIR/weston.log" >&2
  sed -n '1,120p' "$XDG_RUNTIME_DIR/app-wayland.log" >&2
  printf 'Wayland app thoát sớm với code %s.\n' "$exit_code" >&2
  exit 1
fi
SESSION

printf 'Distro X11/Wayland runtime pass: %s\n' "$HYPER_AUTH_DISTRO_LABEL"
CONTAINER
done

printf '%s\n' \
  'Linux distro matrix pass: Ubuntu 22.04/24.04 và Debian 12/13, package-provided Secret Service + Xvfb/Wayland.'
