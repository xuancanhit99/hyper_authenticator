#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
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
  BASE_URL=$(first_env_value SUPABASE_PUBLIC_URL API_EXTERNAL_URL SUPABASE_URL)
fi
BASE_URL=${BASE_URL%/}
PUBLISHABLE_KEY=$(first_env_value SUPABASE_PUBLISHABLE_KEY PUBLISHABLE_KEY ANON_KEY)
SERVICE_ROLE_KEY=$(read_env_value SERVICE_ROLE_KEY)

if [[ -z "$BASE_URL" || -z "$PUBLISHABLE_KEY" || -z "$SERVICE_ROLE_KEY" ]]; then
  printf '%s\n' 'Thiếu public URL, publishable key hoặc service role operator key.' >&2
  exit 78
fi
command -v dart >/dev/null 2>&1 || {
  printf '%s\n' 'Thiếu dart để chạy private Realtime contract.' >&2
  exit 69
}
command -v openssl >/dev/null 2>&1 || {
  printf '%s\n' 'Thiếu openssl để tạo credential test cô lập.' >&2
  exit 69
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-account-sync.XXXXXX")
chmod 700 "$tmp_dir"
user_a_id=
user_b_id=
suffix="$(date +%s)-$$"
email_a="account-sync-a-${suffix}@example.invalid"
email_b="account-sync-b-${suffix}@example.invalid"
password="TEST_ONLY-password-${suffix}"
secret_entropy=$(openssl rand -base64 256 | LC_ALL=C tr -dc 'A-Z2-7')
test_secret=${secret_entropy:0:32}
[[ ${#test_secret} -eq 32 ]]

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
trap cleanup EXIT INT TERM

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
    | curl --max-time 15 -fsS \
        "$BASE_URL/auth/v1/token?grant_type=password" \
        -H "apikey: $PUBLISHABLE_KEY" \
        -H 'Content-Type: application/json' -d @- >"$output"
}

rpc() {
  local token=$1 function_name=$2 body=$3 output=$4
  curl --max-time 15 -sS -o "$output" -w '%{http_code}' \
    "$BASE_URL/rest/v1/rpc/$function_name" -X POST \
    -H "apikey: $PUBLISHABLE_KEY" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' -d "$body"
}

upsert_body() {
  local account_id=$1 expected_revision=$2 issuer=$3
  jq -cn \
    --arg account_id "$account_id" \
    --argjson expected "$expected_revision" \
    --arg issuer "$issuer" \
    --arg secret "$test_secret" \
    '{
      p_account_id: $account_id,
      p_expected_revision: $expected,
      p_payload: {
        issuer: $issuer,
        accountName: "not-a-real-account@example.test",
        secretKey: $secret,
        algorithm: "SHA1",
        digits: 6,
        period: 30
      }
    }'
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

is_success() { (( $1 >= 200 && $1 < 300 )); }
is_client_error() { (( $1 >= 400 && $1 < 500 )); }
run_realtime_contract() {
  (cd "$ROOT" && dart run tool/agent/test_account_sync_realtime.dart "$1")
}

create_user "$email_a" "$tmp_dir/user-a.json"
create_user "$email_b" "$tmp_dir/user-b.json"
user_a_id=$(jq -r '.id // empty' "$tmp_dir/user-a.json")
user_b_id=$(jq -r '.id // empty' "$tmp_dir/user-b.json")
sign_in "$email_a" "$tmp_dir/session-a.json"
sign_in "$email_b" "$tmp_dir/session-b.json"
token_a=$(jq -r '.access_token // empty' "$tmp_dir/session-a.json")
token_b=$(jq -r '.access_token // empty' "$tmp_dir/session-b.json")
check 'Tạo hai isolated user' test -n "$user_a_id$user_b_id$token_a$token_b"

anonymous_status=$(curl --max-time 15 -sS -o "$tmp_dir/anonymous.json" \
  -w '%{http_code}' "$BASE_URL/rest/v1/rpc/list_authenticator_accounts" \
  -X POST -H "apikey: $PUBLISHABLE_KEY" \
  -H 'Content-Type: application/json' -d '{}')
check 'Anonymous không gọi được list RPC' is_client_error "$anonymous_status"

direct_status=$(curl --max-time 15 -sS -o "$tmp_dir/direct.json" \
  -w '%{http_code}' "$BASE_URL/rest/v1/authenticator_accounts?select=*" \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a")
check 'Authenticated không đọc trực tiếp sync table' is_client_error "$direct_status"

account_id=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
status=$(rpc "$token_a" upsert_authenticator_account \
  "$(upsert_body "$account_id" 0 'TEST ONLY')" "$tmp_dir/upsert-a1.json")
check 'User A tạo revision 1' is_success "$status"
check 'Upsert trả đúng non-secret metadata' jq -e \
  'length == 1 and .[0].revision == 1 and .[0].deleted_at == null' \
  "$tmp_dir/upsert-a1.json"

status=$(rpc "$token_a" list_authenticator_accounts '{}' "$tmp_dir/list-a.json")
check 'User A list record đã tạo' is_success "$status"
check 'List trả payload đúng user' jq -e \
  --arg secret "$test_secret" \
  'length == 1 and .[0].payload.issuer == "TEST ONLY" and
   .[0].payload.secretKey == $secret' "$tmp_dir/list-a.json"

status=$(rpc "$token_b" list_authenticator_accounts '{}' "$tmp_dir/list-b.json")
check 'User B list thành công' is_success "$status"
check 'User B không đọc record User A' jq -e 'length == 0' "$tmp_dir/list-b.json"

conflict_status=$(rpc "$token_a" upsert_authenticator_account \
  "$(upsert_body "$account_id" 0 'STALE')" "$tmp_dir/conflict.json")
check 'Stale revision bị từ chối' is_client_error "$conflict_status"
check 'Conflict dùng PT409' jq -e \
  '.code == "PT409" and ((.message // "") | contains("revision_conflict"))' \
  "$tmp_dir/conflict.json"

status=$(rpc "$token_a" upsert_authenticator_account \
  "$(upsert_body "$account_id" 1 'TEST EDITED')" "$tmp_dir/upsert-a2.json")
check 'User A update revision 2' is_success "$status"

status=$(rpc "$token_b" upsert_authenticator_account \
  "$(upsert_body "$account_id" 0 'USER B TEST')" "$tmp_dir/upsert-b1.json")
check 'Hai user có thể dùng cùng stable UUID mà không xung đột tenant' \
  is_success "$status"

delete_body=$(jq -cn --arg id "$account_id" \
  '{p_account_id: $id, p_expected_revision: 2}')
status=$(rpc "$token_a" delete_authenticator_account "$delete_body" \
  "$tmp_dir/delete-a.json")
check 'User A delete tạo tombstone revision 3' is_success "$status"
check 'Delete response không trả payload' jq -e \
  'length == 1 and .[0].revision == 3 and .[0].deleted_at != null and
   .[0].payload == null' "$tmp_dir/delete-a.json"

tombstone_status=$(rpc "$token_a" upsert_authenticator_account \
  "$(upsert_body "$account_id" 3 'REVIVE')" "$tmp_dir/tombstoned.json")
check 'Stale client không revive tombstone' is_client_error "$tombstone_status"
check 'Tombstone dùng PT410' jq -e '.code == "PT410"' \
  "$tmp_dir/tombstoned.json"

status=$(rpc "$token_b" list_authenticator_accounts '{}' "$tmp_dir/list-b2.json")
check 'User B vẫn đọc record riêng sau User A xóa' is_success "$status"
check 'User B record không bị cross-user delete' jq -e \
  'length == 1 and .[0].revision == 1 and .[0].deleted_at == null' \
  "$tmp_dir/list-b2.json"

for legacy_object in encrypted_vault_snapshots synced_accounts \
  authenticator_device_sessions authenticator_device_keys \
  authenticator_device_key_wraps; do
  status=$(curl --max-time 15 -sS -o "$tmp_dir/$legacy_object.json" \
    -w '%{http_code}' "$BASE_URL/rest/v1/$legacy_object?select=*&limit=1" \
    -H "apikey: $PUBLISHABLE_KEY" \
    -H "Authorization: Bearer $token_a")
  check "Legacy table $legacy_object không còn expose" is_client_error "$status"
done

realtime_config="$tmp_dir/realtime-contract.json"
jq -n \
  --arg base_url "$BASE_URL" \
  --arg publishable_key "$PUBLISHABLE_KEY" \
  --arg user_a_id "$user_a_id" \
  --arg access_token_a "$token_a" \
  --arg access_token_b "$token_b" \
  --arg account_id 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' \
  --arg test_secret "$test_secret" \
  '{
    baseUrl: $base_url,
    publishableKey: $publishable_key,
    userAId: $user_a_id,
    accessTokenA: $access_token_a,
    accessTokenB: $access_token_b,
    accountId: $account_id,
    testSecret: $test_secret
  }' >"$realtime_config"
chmod 0600 "$realtime_config"
check 'Private Realtime own-topic/cross-user/client-send/payload contract' \
  run_realtime_contract "$realtime_config"

for user_id in "$user_a_id" "$user_b_id"; do
  curl --max-time 15 -fsS -o /dev/null -X DELETE \
    "$BASE_URL/auth/v1/admin/users/$user_id" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY"
done
user_a_id=
user_b_id=
check 'Isolated users đã cleanup' true

printf 'Account-managed sync remote contract pass: %s checks.\n' "$pass"
