#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${1:-}
CONFIRMATION=${2:-}
HISTORICAL_COMMIT='8e381debfe680ac906de391b4d9274e49acf9c06'
HISTORICAL_VERSION='1.0.0+9'
SECRET_ACCOUNT='app.hyperz.authenticator.secureStorage'

if [[ -z "$ENV_FILE" ||
  "$CONFIRMATION" != '--allow-historical-vault-migration' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/linux_historical_upgrade.sh ENV_FILE --allow-historical-vault-migration' >&2
  exit 64
fi

if [[ $(uname -s) != Linux ||
  ${CI:-} != true ||
  ${GITHUB_ACTIONS:-} != true ||
  ${RUNNER_ENVIRONMENT:-} != github-hosted ||
  ${RUNNER_OS:-} != Linux ]]; then
  printf '%s\n' \
    'Từ chối chạy: historical vault gate chỉ dành cho GitHub-hosted Linux runner tạm.' >&2
  exit 65
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy public runtime config: %s\n' "$ENV_FILE" >&2
  exit 66
fi

for command in \
  dbus-run-session git gnome-keyring-daemon python3 realpath secret-tool \
  xvfb-run; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu Linux historical dependency: %s\n' "$command" >&2
    exit 69
  fi
done

umask 077
ENV_FILE=$(realpath "$ENV_FILE")
SANDBOX=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-linux-history.XXXXXX")
ARCHIVE="$SANDBOX/historical.tar"
HISTORICAL_ROOT="$SANDBOX/source"

cleanup() {
  find "$SANDBOX" -depth -delete
}
trap cleanup EXIT

mkdir -p \
  "$HISTORICAL_ROOT" \
  "$SANDBOX/config" \
  "$SANDBOX/data" \
  "$SANDBOX/cache" \
  "$SANDBOX/runtime"
chmod 0700 "$SANDBOX" "$SANDBOX"/*

cd "$ROOT"
git cat-file -e "$HISTORICAL_COMMIT^{commit}"
git archive --format=tar --output="$ARCHIVE" "$HISTORICAL_COMMIT"
tar -xf "$ARCHIVE" -C "$HISTORICAL_ROOT"

historical_pubspec="$HISTORICAL_ROOT/pubspec.yaml"
grep -Fqx "version: $HISTORICAL_VERSION" "$historical_pubspec"
python3 - "$historical_pubspec" <<'PYTHON'
from pathlib import Path
import sys

path = Path(sys.argv[1])
contents = path.read_text()
anchor = 'dev_dependencies:\n'
if anchor not in contents:
    raise SystemExit('Không tìm thấy dev_dependencies anchor trong historical pubspec.')
path.write_text(contents.replace(
    anchor,
    'dev_dependencies:\n  integration_test:\n    sdk: flutter\n',
    1,
))
PYTHON

cat > "$HISTORICAL_ROOT/.env" <<'ENV'
SUPABASE_URL=https://example.invalid
SUPABASE_ANON_KEY=TEST_ONLY_PUBLIC_KEY
ENV
mkdir -p "$HISTORICAL_ROOT/integration_test"
cp \
  "$ROOT/tool/fixtures/linux_historical_seed_test.dart" \
  "$HISTORICAL_ROOT/integration_test/linux_historical_seed_test.dart"

cd "$HISTORICAL_ROOT"
flutter pub get
if ! awk '
  $1 == "flutter_secure_storage_linux:" { package = 1; next }
  package && $1 == "version:" { exit $2 == "\"1.2.2\"" ? 0 : 1 }
  package && /^[^ ]/ { exit 1 }
  END { if (!package) exit 1 }
' pubspec.lock; then
  printf '%s\n' \
    'Historical dependency drift: cần flutter_secure_storage_linux 1.2.2.' >&2
  exit 1
fi

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$ENV_FILE"

export HYPER_AUTH_TEST_ROOT="$ROOT"
export HYPER_AUTH_HISTORICAL_ROOT="$HISTORICAL_ROOT"
export HYPER_AUTH_TEST_ENV_FILE="$ENV_FILE"
export HYPER_AUTH_SECRET_ACCOUNT="$SECRET_ACCOUNT"
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_CACHE_HOME="$SANDBOX/cache"
export XDG_RUNTIME_DIR="$SANDBOX/runtime"

dbus-run-session -- bash <<'SESSION'
set -euo pipefail

eval "$(printf '\n' | gnome-keyring-daemon --unlock 2>/dev/null)"
eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)"

clear_test_secret() {
  secret-tool clear account "$HYPER_AUTH_SECRET_ACCOUNT" >/dev/null 2>&1 || true
}
trap clear_test_secret EXIT
clear_test_secret

cd "$HYPER_AUTH_HISTORICAL_ROOT"
xvfb-run --auto-servernum --server-args='-screen 0 1280x1024x24' \
  flutter test integration_test/linux_historical_seed_test.dart \
  --device-id linux \
  --dart-define=ALLOW_LINUX_HISTORICAL_VAULT_MUTATION=true

if ! secret-tool lookup account "$HYPER_AUTH_SECRET_ACCOUNT" \
  >/dev/null 2>&1; then
  printf '%s\n' \
    'Bản lịch sử không tạo secret trong private Linux keyring.' >&2
  exit 1
fi

cd "$HYPER_AUTH_TEST_ROOT"
xvfb-run --auto-servernum --server-args='-screen 0 1280x1024x24' \
  flutter test integration_test/linux_historical_upgrade_test.dart \
  --device-id linux \
  --dart-define-from-file="$HYPER_AUTH_TEST_ENV_FILE" \
  --dart-define=ALLOW_LINUX_HISTORICAL_VAULT_MUTATION=true
SESSION

printf '%s\n' \
  'Linux historical upgrade pass: 1.0.0+9 libsecret vault -> current COW v2, field round-trip và cleanup.'
