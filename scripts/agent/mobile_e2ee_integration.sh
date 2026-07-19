#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${1:-}
DEVICE_ID=${2:-}
CONFIRMATION=${3:-}

if [[ -z "$ENV_FILE" || -z "$DEVICE_ID" ||
  "$CONFIRMATION" != '--allow-emulator-vault-reset' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/mobile_e2ee_integration.sh ENV DEVICE_ID --allow-emulator-vault-reset' >&2
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
  printf '%s\n' 'Từ chối truyền service-role key vào mobile client.' >&2
  exit 78
fi
for command in dart flutter jq; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Thiếu command: %s\n' "$command" >&2
    exit 69
  }
done

device=$(flutter devices --machine | jq -ce --arg id "$DEVICE_ID" '
  [.[] | select(.id == $id)] |
  if length == 1 then .[0] else error("device không tồn tại") end
')
if [[ $(jq -r '.emulator' <<<"$device") != true ]]; then
  printf '%s\n' 'Từ chối reset vault trên thiết bị thật.' >&2
  exit 65
fi
target_platform=$(jq -r '.targetPlatform' <<<"$device")
case "$target_platform" in
  android-* | ios) ;;
  *)
    printf 'Target không phải Android emulator/iOS Simulator: %s\n' \
      "$target_platform" >&2
    exit 65
    ;;
esac

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

sandbox=$(mktemp -d \
  "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-mobile-e2ee.XXXXXX")
config="$sandbox/client-test-config.json"
email_input="$sandbox/email"
password_input="$sandbox/password"
cleanup() {
  find "$sandbox" -depth -delete
}
trap cleanup EXIT
chmod 0700 "$sandbox"
umask 077
printf '%s' "$E2EE_TEST_EMAIL" >"$email_input"
printf '%s' "$E2EE_TEST_PASSWORD" >"$password_input"
unset E2EE_TEST_EMAIL E2EE_TEST_PASSWORD
jq -n \
  --arg supabase_url "$supabase_url" \
  --arg publishable_key "$publishable_key" \
  --arg recovery_url "$recovery_url" \
  --rawfile email "$email_input" \
  --rawfile password "$password_input" \
  '{
    SUPABASE_URL: $supabase_url,
    SUPABASE_PUBLISHABLE_KEY: $publishable_key,
    PASSWORD_RECOVERY_URL: $recovery_url,
    ALLOW_INSECURE_PLAINTEXT_SYNC: false,
    ALLOW_E2EE_REMOTE_TEST_MUTATION: true,
    E2EE_TEST_EMAIL: $email,
    E2EE_TEST_PASSWORD: $password
  }' >"$config"
chmod 0600 "$config"
rm -f "$email_input" "$password_input"

flutter test integration_test/encrypted_sync_smoke_test.dart \
  --device-id "$DEVICE_ID" \
  --dart-define-from-file="$config"

printf 'Mobile E2EE integration pass: %s (%s).\n' \
  "$DEVICE_ID" "$target_platform"
