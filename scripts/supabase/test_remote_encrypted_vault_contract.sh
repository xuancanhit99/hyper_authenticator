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

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-e2ee-contract.XXXXXX")
chmod 700 "$tmp_dir"
user_a_id=
user_b_id=
suffix="$(date +%s)-$$"
email_a="e2ee-a-${suffix}@example.invalid"
email_b="e2ee-b-${suffix}@example.invalid"
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
  local email=$1
  local output=$2
  jq -cn --arg email "$email" --arg password "$password" \
    '{email: $email, password: $password, email_confirm: true}' \
    | curl --max-time 15 -fsS "$BASE_URL/auth/v1/admin/users" -X POST \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H 'Content-Type: application/json' -d @- >"$output"
}

sign_in() {
  local email=$1
  local output=$2
  jq -cn --arg email "$email" --arg password "$password" \
    '{email: $email, password: $password}' \
    | curl --max-time 15 -fsS "$BASE_URL/auth/v1/token?grant_type=password" \
        -H "apikey: $PUBLISHABLE_KEY" \
        -H 'Content-Type: application/json' -d @- >"$output"
}

publish() {
  local token=$1
  local expected_revision=$2
  local output=$3
  local wrapped_key_ciphertext=${4:-TEST_ONLY_WRAPPED_KEY_CIPHERTEXT_1234567890}
  jq -cn \
    --argjson expected "$expected_revision" \
    --arg wrapped_key_ciphertext "$wrapped_key_ciphertext" '{
    p_expected_revision: $expected,
    p_format_version: 1,
    p_cipher: "AES-256-GCM",
    p_nonce: "AAAAAAAAAAAAAAAA",
    p_ciphertext: "TEST_ONLY_CIPHERTEXT",
    p_auth_tag: "AAAAAAAAAAAAAAAAAAAAAA==",
    p_key_format_version: 1,
    p_wrapped_key_nonce: "BBBBBBBBBBBBBBBB",
    p_wrapped_key_ciphertext: $wrapped_key_ciphertext,
    p_wrapped_key_auth_tag: "BBBBBBBBBBBBBBBBBBBBBB=="
  }' | curl --max-time 15 -sS -o "$output" -w '%{http_code}' \
      "$BASE_URL/rest/v1/rpc/publish_encrypted_vault_snapshot" -X POST \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' -d @-
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

sessions_ready() {
  [[ -n "$user_a_id" && -n "$user_b_id" && -n "$token_a" && -n "$token_b" ]]
}

create_user "$email_a" "$tmp_dir/user-a.json"
create_user "$email_b" "$tmp_dir/user-b.json"
user_a_id=$(jq -r '.id // empty' "$tmp_dir/user-a.json")
user_b_id=$(jq -r '.id // empty' "$tmp_dir/user-b.json")
sign_in "$email_a" "$tmp_dir/session-a.json"
sign_in "$email_b" "$tmp_dir/session-b.json"
token_a=$(jq -r '.access_token // empty' "$tmp_dir/session-a.json")
token_b=$(jq -r '.access_token // empty' "$tmp_dir/session-b.json")
check 'Tạo hai isolated user/session' sessions_ready

anonymous_status=$(curl --max-time 15 -sS -o "$tmp_dir/anonymous.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision" \
  -H "apikey: $PUBLISHABLE_KEY")
check 'Anonymous không SELECT encrypted table' test "$anonymous_status" -ge 400

first_status=$(publish "$token_a" 0 "$tmp_dir/publish-1.json")
check 'User A publish revision đầu' test "$first_status" -eq 200
check 'Server trả revision 1' jq -e 'length == 1 and .[0].revision == 1' \
  "$tmp_dir/publish-1.json"

curl --max-time 15 -fsS "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=*" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_a" \
  >"$tmp_dir/select-a.json"
curl --max-time 15 -fsS "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_b" \
  >"$tmp_dir/select-b.json"
check 'User A chỉ nhận encrypted shape' jq -e \
  'length == 1 and .[0].cipher == "AES-256-GCM" and
   (.[0] | has("secret_key") | not) and (.[0] | has("issuer") | not)' \
  "$tmp_dir/select-a.json"
check 'User B không SELECT row User A' jq -e 'length == 0' "$tmp_dir/select-b.json"

stale_status=$(publish "$token_a" 0 "$tmp_dir/stale.json")
check 'Stale revision trả HTTP 409' test "$stale_status" -eq 409
check 'Conflict không trả encrypted payload' jq -e \
  '(.message // "") | contains("revision_conflict")' "$tmp_dir/stale.json"

rotated_wrapped_key='TEST_ONLY_ROTATED_WRAPPED_KEY_CIPHERTEXT_123456'
second_status=$(publish \
  "$token_a" 1 "$tmp_dir/publish-2.json" "$rotated_wrapped_key")
check 'Expected revision đúng publish được' test "$second_status" -eq 200
check 'Server tăng revision lên 2' jq -e '.[0].revision == 2' \
  "$tmp_dir/publish-2.json"

curl --max-time 15 -fsS \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision,wrapped_key_ciphertext" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_a" \
  >"$tmp_dir/select-rotated-key.json"
check 'Revision mới atomically thay wrapped recovery key' jq -e \
  --arg wrapped_key "$rotated_wrapped_key" \
  'length == 1 and .[0].revision == 2 and
   .[0].wrapped_key_ciphertext == $wrapped_key' \
  "$tmp_dir/select-rotated-key.json"

spoof_status=$(publish "$token_b" 2 "$tmp_dir/spoof.json")
check 'User B không update row User A qua RPC' test "$spoof_status" -ge 400

printf 'Encrypted remote contract pass: %s checks.\n' "$pass"
