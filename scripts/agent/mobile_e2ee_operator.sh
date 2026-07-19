#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CLIENT_ENV_FILE=${1:-}
OPERATOR_ENV_FILE=${2:-}
DEVICE_ID=${3:-}
CONFIRMATION=${4:-}

if [[ -z "$CLIENT_ENV_FILE" || -z "$OPERATOR_ENV_FILE" ||
  -z "$DEVICE_ID" ||
  "$CONFIRMATION" != '--allow-isolated-user-and-emulator-vault-reset' ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/mobile_e2ee_operator.sh CLIENT_ENV OPERATOR_ENV DEVICE_ID --allow-isolated-user-and-emulator-vault-reset' >&2
  printf '%s\n' \
    'OPERATOR_ENV phải là file 0600 ngoài repository, chứa SERVICE_ROLE_KEY.' >&2
  exit 64
fi

for path in "$CLIENT_ENV_FILE" "$OPERATOR_ENV_FILE"; do
  if [[ ! -f "$path" ]]; then
    printf 'Không tìm thấy env file: %s\n' "$path" >&2
    exit 66
  fi
done

CLIENT_ENV_FILE=$(realpath "$CLIENT_ENV_FILE")
OPERATOR_ENV_FILE=$(realpath "$OPERATOR_ENV_FILE")
if [[ "$CLIENT_ENV_FILE" == "$OPERATOR_ENV_FILE" ]]; then
  printf '%s\n' 'Client env và operator env phải tách biệt.' >&2
  exit 78
fi
case "$OPERATOR_ENV_FILE" in
  "$ROOT"/*)
    printf '%s\n' 'Operator env phải nằm ngoài repository.' >&2
    exit 78
    ;;
esac

operator_mode=$(stat -f '%Lp' "$OPERATOR_ENV_FILE" 2>/dev/null ||
  stat -c '%a' "$OPERATOR_ENV_FILE")
if (( (8#$operator_mode & 8#077) != 0 )); then
  printf 'Operator env phải có mode 0600 hoặc chặt hơn, hiện là %s.\n' \
    "$operator_mode" >&2
  exit 78
fi

for command in curl dart jq openssl; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Thiếu mobile E2EE operator dependency: %s\n' "$command" >&2
    exit 69
  }
done

cd "$ROOT"
dart run tool/agent/check_release_config.dart "$CLIENT_ENV_FILE"

read_env_value() {
  local file=$1
  local key=$2
  awk -v key="$key" \
    'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' \
    "$file"
}

first_env_value() {
  local file=$1
  shift
  local key value
  for key in "$@"; do
    value=$(read_env_value "$file" "$key")
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
}

service_role_key=$(read_env_value "$OPERATOR_ENV_FILE" SERVICE_ROLE_KEY)
base_url=$(first_env_value \
  "$OPERATOR_ENV_FILE" SUPABASE_PUBLIC_URL API_EXTERNAL_URL SUPABASE_URL)
if [[ -z "$base_url" ]]; then
  if jq -e 'type == "object"' "$CLIENT_ENV_FILE" >/dev/null 2>&1; then
    base_url=$(jq -r '.SUPABASE_URL // empty' "$CLIENT_ENV_FILE")
  else
    base_url=$(read_env_value "$CLIENT_ENV_FILE" SUPABASE_URL)
  fi
fi
base_url=${base_url%/}

if [[ -z "$service_role_key" || ! "$base_url" =~ ^https://[^/]+ ]]; then
  printf '%s\n' 'Operator env thiếu SERVICE_ROLE_KEY hoặc HTTPS Supabase URL.' >&2
  exit 78
fi

operator_tmp=$(mktemp -d \
  "${TMPDIR:-/tmp}/hyper-auth-mobile-e2ee-operator.XXXXXX")
operator_headers="$operator_tmp/operator.headers"
create_request="$operator_tmp/create-user.json"
create_response="$operator_tmp/create-user-response.json"
delete_response="$operator_tmp/delete-user-response.json"
email_input="$operator_tmp/email"
password_input="$operator_tmp/password"
user_id=

write_operator_headers() {
  umask 077
  {
    printf 'apikey: %s\n' "$service_role_key"
    printf 'Authorization: Bearer %s\n' "$service_role_key"
  } >"$operator_headers"
  chmod 0600 "$operator_headers"
}

best_effort_delete_user() {
  if [[ -z "$user_id" ]]; then
    return
  fi
  write_operator_headers
  curl --max-time 20 -sS -o /dev/null -X DELETE \
    "$base_url/auth/v1/admin/users/$user_id" \
    -H "@$operator_headers" || true
  rm -f "$operator_headers"
}

cleanup() {
  best_effort_delete_user
  service_role_key=
  find "$operator_tmp" -depth -delete
}
trap cleanup EXIT
chmod 0700 "$operator_tmp"
umask 077

suffix="$(date +%s)-$$"
test_email="e2ee-mobile-${suffix}@example.invalid"
test_password="TEST_ONLY-$(openssl rand -hex 18)"
printf '%s' "$test_email" >"$email_input"
printf '%s' "$test_password" >"$password_input"
jq -cn --rawfile email "$email_input" --rawfile password "$password_input" \
  '{email: $email, password: $password, email_confirm: true}' >"$create_request"
rm -f "$email_input" "$password_input"

write_operator_headers
curl --max-time 20 -fsS "$base_url/auth/v1/admin/users" -X POST \
  -H "@$operator_headers" \
  -H 'Content-Type: application/json' -d @"$create_request" >"$create_response"
rm -f "$operator_headers" "$create_request"

user_id=$(jq -r '.id // empty' "$create_response")
if [[ -z "$user_id" ]]; then
  printf '%s\n' 'Supabase không trả ID cho isolated mobile E2EE user.' >&2
  exit 1
fi
rm -f "$create_response"
printf '%s\n' 'MOBILE_E2EE_OPERATOR_PHASE=isolated-user-created'

runtime_status=0
E2EE_TEST_EMAIL="$test_email" E2EE_TEST_PASSWORD="$test_password" \
  scripts/agent/mobile_e2ee_integration.sh \
  "$CLIENT_ENV_FILE" "$DEVICE_ID" --allow-emulator-vault-reset || \
  runtime_status=$?
test_email=
test_password=

write_operator_headers
delete_status=$(curl --max-time 20 -sS -o "$delete_response" -w '%{http_code}' \
  -X DELETE "$base_url/auth/v1/admin/users/$user_id" \
  -H "@$operator_headers")
verify_status=$(curl --max-time 20 -sS -o /dev/null -w '%{http_code}' \
  "$base_url/auth/v1/admin/users/$user_id" \
  -H "@$operator_headers")
rm -f "$operator_headers" "$delete_response"

if [[ "$delete_status" != 200 && "$delete_status" != 204 ]]; then
  printf 'Không xóa được isolated mobile E2EE user (HTTP %s).\n' \
    "$delete_status" >&2
  exit 1
fi
if [[ "$verify_status" != 404 ]]; then
  printf 'Isolated mobile E2EE user còn tồn tại sau cleanup (HTTP %s).\n' \
    "$verify_status" >&2
  exit 1
fi
user_id=
printf '%s\n' 'MOBILE_E2EE_OPERATOR_PHASE=remote-cleanup-verified'

if [[ $runtime_status -ne 0 ]]; then
  printf 'Mobile E2EE runtime thất bại với exit code %s.\n' \
    "$runtime_status" >&2
  exit "$runtime_status"
fi

printf '%s\n' \
  'Mobile E2EE operator pass: isolated user lifecycle và runtime đều sạch.'
