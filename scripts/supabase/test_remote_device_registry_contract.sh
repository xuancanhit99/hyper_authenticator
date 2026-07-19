#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${1:-.env}
BASE_URL=${2:-}

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy Supabase env file: %s\n' "$ENV_FILE" >&2
  exit 66
fi

read_env_value() {
  local key=$1
  awk -v key="$key" \
    'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' \
    "$ENV_FILE"
}

first_env_value() {
  local key value
  for key in "$@"; do
    value=$(read_env_value "$key")
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
}

if [[ -z "$BASE_URL" ]]; then
  BASE_URL=$(first_env_value SUPABASE_PUBLIC_URL API_EXTERNAL_URL)
fi
PUBLISHABLE_KEY=$(first_env_value SUPABASE_PUBLISHABLE_KEY PUBLISHABLE_KEY ANON_KEY)
SERVICE_ROLE_KEY=$(read_env_value SERVICE_ROLE_KEY)

if [[ -z "$BASE_URL" || -z "$PUBLISHABLE_KEY" || -z "$SERVICE_ROLE_KEY" ]]; then
  printf '%s\n' 'Thiếu public URL, publishable key hoặc service role operator key.' >&2
  exit 78
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-device-contract.XXXXXX")
chmod 700 "$tmp_dir"
user_a_id=
user_b_id=
suffix="$(date +%s)-$$"
email_a="device-a-${suffix}@example.invalid"
email_b="device-b-${suffix}@example.invalid"
password="TEST_ONLY-password-${suffix}"

cleanup() {
  for user_id in "$user_a_id" "$user_b_id"; do
    if [[ -n "$user_id" ]]; then
      curl --max-time 15 -fsS -o /dev/null -X DELETE \
        "$BASE_URL/auth/v1/admin/users/$user_id" \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" || true
    fi
  done
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT

create_user() {
  local email=$1 output=$2
  jq -cn --arg email "$email" --arg password "$password" \
    '{email: $email, password: $password, email_confirm: true}' \
    | curl --max-time 15 -fsS "$BASE_URL/auth/v1/admin/users" -X POST \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H 'Content-Type: application/json' -d @- >"$output"
}

sign_in() {
  local email=$1 output=$2
  jq -cn --arg email "$email" --arg password "$password" \
    '{email: $email, password: $password}' \
    | curl --max-time 15 -fsS "$BASE_URL/auth/v1/token?grant_type=password" \
        -H "apikey: $PUBLISHABLE_KEY" \
        -H 'Content-Type: application/json' -d @- >"$output"
}

rpc() {
  local function_name=$1 token=$2 payload=$3 output=$4
  curl --max-time 15 -sS -o "$output" -w '%{http_code}' \
    "$BASE_URL/rest/v1/rpc/$function_name" -X POST \
    -H "apikey: $PUBLISHABLE_KEY" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' -d "$payload"
}

register_device() {
  local token=$1 installation_id=$2 name=$3 platform=$4 output=$5
  local payload
  payload=$(jq -cn \
    --arg installation_id "$installation_id" \
    --arg name "$name" \
    --arg platform "$platform" '{
      p_installation_id: $installation_id,
      p_display_name: $name,
      p_platform: $platform
    }')
  rpc register_current_authenticator_device "$token" "$payload" "$output"
}

list_devices() {
  local token=$1 output=$2
  rpc list_authenticator_device_sessions "$token" '{}' "$output"
}

revoke_device() {
  local token=$1 registration_id=$2 output=$3
  local payload
  payload=$(jq -cn --arg registration_id "$registration_id" \
    '{p_registration_id: $registration_id}')
  rpc revoke_authenticator_device_session "$token" "$payload" "$output"
}

pass=0
check() {
  local name=$1
  shift
  if "$@" >/dev/null; then
    printf '  PASS: %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  FAIL: %s\n' "$name" >&2
    exit 1
  fi
}

is_success_status() { (( $1 >= 200 && $1 < 300 )); }
is_client_error_status() { (( $1 >= 400 && $1 < 500 )); }

create_user "$email_a" "$tmp_dir/user-a.json"
create_user "$email_b" "$tmp_dir/user-b.json"
user_a_id=$(jq -r '.id // empty' "$tmp_dir/user-a.json")
user_b_id=$(jq -r '.id // empty' "$tmp_dir/user-b.json")
sign_in "$email_a" "$tmp_dir/session-a-old.json"
sign_in "$email_a" "$tmp_dir/session-a-current.json"
sign_in "$email_b" "$tmp_dir/session-b.json"
token_a_old=$(jq -r '.access_token // empty' "$tmp_dir/session-a-old.json")
refresh_a_old=$(jq -r '.refresh_token // empty' "$tmp_dir/session-a-old.json")
token_a=$(jq -r '.access_token // empty' "$tmp_dir/session-a-current.json")
token_b=$(jq -r '.access_token // empty' "$tmp_dir/session-b.json")
check 'Tạo hai user và hai session riêng cho User A' test \
  -n "$user_a_id$user_b_id$token_a_old$refresh_a_old$token_a$token_b"
check 'Hai access token User A khác nhau' test "$token_a" != "$token_a_old"

status=$(register_device "$token_a_old" \
  10000000-0000-4000-8000-000000000001 \
  'Hyper Authenticator trên Android' android "$tmp_dir/register-a-old.json")
check 'Session cũ User A tự đăng ký' is_success_status "$status"
registration_a_old=$(jq -r '.[0].registration_id // empty' \
  "$tmp_dir/register-a-old.json")
check 'Registry trả opaque registration ID' test -n "$registration_a_old"

status=$(register_device "$token_a" \
  10000000-0000-4000-8000-000000000002 \
  'Hyper Authenticator trên Linux' linux "$tmp_dir/register-a-current.json")
check 'Session hiện tại User A tự đăng ký' is_success_status "$status"
registration_a=$(jq -r '.[0].registration_id // empty' \
  "$tmp_dir/register-a-current.json")

status=$(register_device "$token_b" \
  20000000-0000-4000-8000-000000000001 \
  'Hyper Authenticator trên Windows' windows "$tmp_dir/register-b.json")
check 'User B tự đăng ký độc lập' is_success_status "$status"
registration_b=$(jq -r '.[0].registration_id // empty' "$tmp_dir/register-b.json")

status=$(list_devices "$token_a" "$tmp_dir/list-a.json")
check 'User A list device registry' is_success_status "$status"
check 'User A thấy đúng hai record và một current' jq -e \
  'length == 2 and ([.[] | select(.is_current == true)] | length) == 1' \
  "$tmp_dir/list-a.json"
check 'List không lộ session ID, IP hoặc user agent' jq -e \
  'all(.[]; (has("session_id") or has("ip") or has("user_agent")) | not)' \
  "$tmp_dir/list-a.json"

status=$(list_devices "$token_b" "$tmp_dir/list-b.json")
check 'User B list registry riêng' is_success_status "$status"
check 'User B không thấy registration của User A' jq -e \
  --arg a "$registration_a" --arg a_old "$registration_a_old" \
  'length == 1 and all(.[]; .registration_id != $a and .registration_id != $a_old)' \
  "$tmp_dir/list-b.json"

direct_status=$(curl --max-time 15 -sS -o "$tmp_dir/direct-table.json" \
  -w '%{http_code}' \
  "$BASE_URL/rest/v1/authenticator_device_sessions?select=registration_id" \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a")
check 'Authenticated client không SELECT trực tiếp registry table' \
  is_client_error_status "$direct_status"

anonymous_status=$(curl --max-time 15 -sS -o "$tmp_dir/anonymous-list.json" \
  -w '%{http_code}' "$BASE_URL/rest/v1/rpc/list_authenticator_device_sessions" \
  -X POST -H "apikey: $PUBLISHABLE_KEY" \
  -H 'Content-Type: application/json' -d '{}')
check 'Anonymous không gọi được registry RPC' \
  is_client_error_status "$anonymous_status"

self_status=$(revoke_device "$token_a" "$registration_a" \
  "$tmp_dir/revoke-self.json")
check 'Current session không tự revoke qua device RPC' \
  is_client_error_status "$self_status"
check 'Self revoke trả lỗi rõ và không lộ metadata' jq -e \
  '(.message // "") | contains("cannot_revoke_current_device_session")' \
  "$tmp_dir/revoke-self.json"

cross_status=$(revoke_device "$token_a" "$registration_b" \
  "$tmp_dir/revoke-cross.json")
check 'User A không revoke registry của User B' test "$cross_status" -eq 404
status=$(list_devices "$token_b" "$tmp_dir/list-b-after-cross.json")
check 'Cross-tenant attempt giữ session User B' is_success_status "$status"
check 'User B vẫn còn đúng current record' jq -e \
  'length == 1 and .[0].is_current == true' "$tmp_dir/list-b-after-cross.json"

revoke_status=$(revoke_device "$token_a" "$registration_a_old" \
  "$tmp_dir/revoke-a-old.json")
check 'Current session revoke riêng session cũ' is_success_status "$revoke_status"
check 'Revoke RPC xác nhận true' jq -e '. == true' "$tmp_dir/revoke-a-old.json"

refresh_status=$(jq -cn --arg refresh_token "$refresh_a_old" \
  '{refresh_token: $refresh_token}' | curl --max-time 15 -sS \
    -o "$tmp_dir/refresh-a-old.json" -w '%{http_code}' \
    "$BASE_URL/auth/v1/token?grant_type=refresh_token" -X POST \
    -H "apikey: $PUBLISHABLE_KEY" \
    -H 'Content-Type: application/json' -d @-)
check 'Refresh token của target bị hủy' is_client_error_status "$refresh_status"

old_list_status=$(list_devices "$token_a_old" "$tmp_dir/list-a-old-revoked.json")
check 'Access JWT target bị active-session guard chặn ngay' \
  is_client_error_status "$old_list_status"
check 'JWT target nhận session_revoked' jq -e \
  '(.message // "") | contains("session_revoked")' \
  "$tmp_dir/list-a-old-revoked.json"

status=$(list_devices "$token_a" "$tmp_dir/list-a-final.json")
check 'Current session vẫn list được sau targeted revoke' is_success_status "$status"
check 'Target biến mất, current record được giữ' jq -e \
  --arg current "$registration_a" \
  'length == 1 and .[0].registration_id == $current and .[0].is_current == true' \
  "$tmp_dir/list-a-final.json"

printf 'Device registry remote contract pass: %s checks.\n' "$pass"
