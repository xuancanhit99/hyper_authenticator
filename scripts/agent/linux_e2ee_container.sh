#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${1:-}
CONFIRMATION=${2:-}
FLUTTER_VERSION=3.44.6
UBUNTU_IMAGE='ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90'

if [[ -z "$ENV_FILE" ||
  "$CONFIRMATION" != '--allow-isolated-remote-user' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/linux_e2ee_container.sh ENV_FILE --allow-isolated-remote-user' >&2
  printf '%s\n' \
    'Cần export E2EE_TEST_EMAIL và E2EE_TEST_PASSWORD của isolated test user.' >&2
  exit 64
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy public runtime config: %s\n' "$ENV_FILE" >&2
  exit 66
fi

if [[ -z ${E2EE_TEST_EMAIL:-} || -z ${E2EE_TEST_PASSWORD:-} ]]; then
  printf '%s\n' 'Thiếu isolated E2EE test-user credential.' >&2
  exit 78
fi

if [[ -n ${SUPABASE_SERVICE_ROLE_KEY:-} || -n ${SERVICE_ROLE_KEY:-} ]]; then
  printf '%s\n' \
    'Từ chối chạy: không truyền service-role key vào Docker/client harness.' >&2
  exit 78
fi

for command in dart docker git jq tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu container harness dependency: %s\n' "$command" >&2
    exit 69
  fi
done
if ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Docker daemon là bắt buộc cho Linux E2EE runtime.' >&2
  exit 69
fi

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"

read_env_value() {
  local key=$1
  awk -v key="$key" \
    'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' \
    "$ENV_FILE"
}

if jq -e 'type == "object"' "$ENV_FILE" >/dev/null 2>&1; then
  supabase_url=$(jq -r '.SUPABASE_URL // empty' "$ENV_FILE")
  publishable_key=$(jq -r '.SUPABASE_PUBLISHABLE_KEY // empty' "$ENV_FILE")
  recovery_url=$(jq -r '.PASSWORD_RECOVERY_URL // empty' "$ENV_FILE")
else
  supabase_url=$(read_env_value SUPABASE_URL)
  publishable_key=$(read_env_value SUPABASE_PUBLISHABLE_KEY)
  recovery_url=$(read_env_value PASSWORD_RECOVERY_URL)
fi

config_dir=$(mktemp -d \
  "${TMPDIR:-/tmp}/hyper-auth-linux-e2ee-config.XXXXXX")
public_config="$config_dir/public-config.json"
cleanup() {
  find "$config_dir" -depth -delete
}
trap cleanup EXIT
chmod 0700 "$config_dir"
umask 077
jq -n \
  --arg supabase_url "$supabase_url" \
  --arg publishable_key "$publishable_key" \
  --arg recovery_url "$recovery_url" \
  '{
    SUPABASE_URL: $supabase_url,
    SUPABASE_PUBLISHABLE_KEY: $publishable_key,
    PASSWORD_RECOVERY_URL: $recovery_url,
    ALLOW_INSECURE_PLAINTEXT_SYNC: false
  }' >"$public_config"
chmod 0600 "$public_config"
dart run tool/agent/check_release_config.dart "$public_config"

# Chỉ tar tracked/untracked non-ignored source; .env, Git metadata và build output
# ignored không đi vào container. Credential test là user-level, truyền tạm qua
# container env rồi inner harness gỡ trước khi Flutter process khởi chạy.
git ls-files --cached --others --exclude-standard -z |
  COPYFILE_DISABLE=1 tar --no-xattrs --null --files-from=- -cf - |
  docker run --rm --interactive \
    --env CI=true \
    --env E2EE_TEST_EMAIL \
    --env E2EE_TEST_PASSWORD \
    --volume "$public_config:/run/hyper-auth/public-config.json:ro" \
    "$UBUNTU_IMAGE" bash -lc "set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates git curl unzip xz-utils zip \\
  clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev \\
  libjsoncpp-dev liblzma-dev dbus-x11 gnome-keyring libsecret-tools \\
  xvfb xauth jq >/dev/null
git clone --quiet --depth 1 --branch '$FLUTTER_VERSION' \\
  https://github.com/flutter/flutter.git /opt/flutter
export PATH=/opt/flutter/bin:\$PATH
flutter config --no-analytics --enable-linux-desktop >/dev/null
flutter precache --linux >/dev/null
mkdir -p /workspace
tar -xf - -C /workspace
cd /workspace
flutter pub get
scripts/agent/linux_e2ee_integration.sh \\
  /run/hyper-auth/public-config.json --allow-isolated-remote-user"

printf '%s\n' \
  'Linux container E2EE runtime pass; operator vẫn phải xóa isolated user ở server.'
