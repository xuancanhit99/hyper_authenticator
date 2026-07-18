#!/usr/bin/env bash
set -euo pipefail

BASELINE_DEB=${1:-}
CURRENT_DEB=${2:-}
CONFIRMATION=${3:-}
UBUNTU_IMAGE='ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'

if [[ -z "$BASELINE_DEB" || -z "$CURRENT_DEB" ||
  "$CONFIRMATION" != '--allow-container-package-install' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/linux_package_smoke.sh BASELINE_DEB CURRENT_DEB --allow-container-package-install' >&2
  exit 64
fi

if [[ $(uname -s) != Linux || ${CI:-} != true ]]; then
  printf '%s\n' \
    'Từ chối chạy: package smoke chỉ dành cho Linux CI runner tách biệt.' >&2
  exit 65
fi

if [[ ! -f "$BASELINE_DEB" || ! -f "$CURRENT_DEB" ]]; then
  printf '%s\n' 'Thiếu baseline hoặc current Debian package.' >&2
  exit 66
fi

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Docker daemon là bắt buộc cho isolated package smoke.' >&2
  exit 69
fi

SANDBOX=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-package.XXXXXX")
cleanup() {
  find "$SANDBOX" -depth -delete
}
trap cleanup EXIT
install -m 0644 "$BASELINE_DEB" "$SANDBOX/baseline.deb"
install -m 0644 "$CURRENT_DEB" "$SANDBOX/current.deb"

docker run --rm --interactive \
  --mount "type=bind,src=$SANDBOX,dst=/packages,readonly" \
  "$UBUNTU_IMAGE" bash -s <<'CONTAINER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

baseline_version=$(dpkg-deb --field /packages/baseline.deb Version)
current_version=$(dpkg-deb --field /packages/current.deb Version)
[[ $(stat -c '%a' /) == 755 ]]
if ! dpkg --compare-versions "$baseline_version" lt "$current_version"; then
  printf '%s\n' 'Baseline package version phải nhỏ hơn current version.' >&2
  exit 1
fi

apt-get update -qq
apt-get install -y -qq \
  dbus-x11 desktop-file-utils gnome-keyring libgl1-mesa-dri \
  libsecret-tools xauth xvfb >/dev/null

runtime=$(mktemp -d)
chmod 0700 "$runtime"
export XDG_CONFIG_HOME="$runtime/config"
export XDG_DATA_HOME="$runtime/data"
export XDG_CACHE_HOME="$runtime/cache"
export XDG_RUNTIME_DIR="$runtime/run"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 0700 "$runtime"/*

cleanup_container() {
  apt-get remove -y -qq hyper-authenticator >/dev/null 2>&1 || true
  find "$runtime" -depth -delete
}
trap cleanup_container EXIT

apt-get install -y -qq /packages/baseline.deb >/dev/null
[[ $(stat -c '%a' /) == 755 ]]
[[ $(dpkg-query -W -f='${Version}' hyper-authenticator) == "$baseline_version" ]]
test -x /usr/bin/hyper-authenticator
test -f /usr/share/applications/app.hyperz.authenticator.desktop
test -f /usr/share/pixmaps/app.hyperz.authenticator.png
desktop-file-validate /usr/share/applications/app.hyperz.authenticator.desktop
if ldd /opt/hyper-authenticator/hyper_authenticator |
  grep -F 'not found' >/dev/null; then
  printf '%s\n' 'Installed package còn thiếu shared library.' >&2
  exit 1
fi

dbus-run-session -- bash <<'SESSION'
set -euo pipefail
eval "$(printf '\n' | gnome-keyring-daemon --unlock 2>/dev/null)"
eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)"

run_installed_app() {
  local log_file=$1
  set +e
  xvfb-run --auto-servernum --server-args='-screen 0 1280x1024x24' \
    timeout --signal=TERM 8s /usr/bin/hyper-authenticator \
    >"$log_file" 2>&1
  local exit_code=$?
  set -e
  if [[ $exit_code -ne 124 ]]; then
    sed -n '1,120p' "$log_file" >&2
    printf 'Installed app thoát sớm với code %s.\n' "$exit_code" >&2
    exit 1
  fi
}

run_installed_app "$XDG_RUNTIME_DIR/baseline.log"
mkdir -p "$XDG_DATA_HOME/app.hyperz.authenticator"
printf '%s\n' 'preserve-on-upgrade-and-remove' \
  > "$XDG_DATA_HOME/app.hyperz.authenticator/package-retention-sentinel"

apt-get install -y -qq /packages/current.deb >/dev/null
[[ $(stat -c '%a' /) == 755 ]]
current_version=$(dpkg-deb --field /packages/current.deb Version)
[[ $(dpkg-query -W -f='${Version}' hyper-authenticator) == "$current_version" ]]
test -f "$XDG_DATA_HOME/app.hyperz.authenticator/package-retention-sentinel"
run_installed_app "$XDG_RUNTIME_DIR/current.log"

apt-get remove -y -qq hyper-authenticator >/dev/null
[[ $(stat -c '%a' /) == 755 ]]
if dpkg-query -W -f='${Status}' hyper-authenticator 2>/dev/null |
  grep -Fq 'install ok installed'; then
  printf '%s\n' 'Package vẫn ở trạng thái installed sau remove.' >&2
  exit 1
fi
test ! -e /usr/bin/hyper-authenticator
test ! -e /opt/hyper-authenticator
test -f "$XDG_DATA_HOME/app.hyperz.authenticator/package-retention-sentinel"
SESSION

printf '%s\n' \
  'Linux Debian package smoke pass: dependency, install, launch, upgrade, remove và data retention.'
CONTAINER

printf '%s\n' \
  'Linux Debian package container smoke hoàn tất trên Ubuntu 24.04 sạch.'
