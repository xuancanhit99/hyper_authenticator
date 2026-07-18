#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${1:-.env}
BASE_URL=${2:-}

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy Supabase env file: %s\n' "$ENV_FILE" >&2
  exit 66
fi

for command_name in curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu command bắt buộc: %s\n' "$command_name" >&2
    exit 69
  fi
done

read_env_value() {
  local key=$1
  grep -m1 "^${key}=" "$ENV_FILE" | cut -d= -f2-
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
  printf '%s\n' \
    'Thiếu SUPABASE_PUBLIC_URL, SUPABASE_PUBLISHABLE_KEY hoặc SERVICE_ROLE_KEY.' >&2
  exit 78
fi

make_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    tr -d '\n' </proc/sys/kernel/random/uuid
  else
    printf '%s\n' 'Không thể tạo UUID cho isolated test.' >&2
    exit 69
  fi
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-rls.XXXXXX")
chmod 700 "$tmp_dir"

user_a_id=
user_b_id=
account_id=$(make_uuid)
suffix="$(date +%s)-$$"
email_a="rls-a-${suffix}@example.invalid"
email_b="rls-b-${suffix}@example.invalid"
password="TEST_ONLY-password-${suffix}"

cleanup() {
  if [[ -n "$user_a_id" ]]; then
    curl -fsS -o /dev/null \
      -X DELETE "$BASE_URL/auth/v1/admin/users/$user_a_id" \
      -H "apikey: $SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SERVICE_ROLE_KEY" || true
  fi
  if [[ -n "$user_b_id" ]]; then
    curl -fsS -o /dev/null \
      -X DELETE "$BASE_URL/auth/v1/admin/users/$user_b_id" \
      -H "apikey: $SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SERVICE_ROLE_KEY" || true
  fi
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT

pass=0
fail=0

check_equal() {
  local name=$1
  local expected=$2
  local actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  FAIL: %s (expected %s, got %s)\n' \
      "$name" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

create_user() {
  local email=$1
  local output=$2
  local payload
  payload=$(jq -cn \
    --arg email "$email" \
    --arg password "$password" \
    '{email: $email, password: $password, email_confirm: true}')
  curl -fsS "$BASE_URL/auth/v1/admin/users" \
    -X POST \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload" >"$output"
}

sign_in() {
  local email=$1
  local output=$2
  local payload
  payload=$(jq -cn \
    --arg email "$email" \
    --arg password "$password" \
    '{email: $email, password: $password}')
  curl -fsS "$BASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $PUBLISHABLE_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload" >"$output"
}

printf '%s\n' '=== Supabase synced_accounts RLS contract ==='

create_user "$email_a" "$tmp_dir/user-a.json"
user_a_id=$(jq -r '.id // empty' "$tmp_dir/user-a.json")
create_user "$email_b" "$tmp_dir/user-b.json"
user_b_id=$(jq -r '.id // empty' "$tmp_dir/user-b.json")
check_equal 'Tạo hai isolated test user' 'true' \
  "$([[ -n "$user_a_id" && -n "$user_b_id" ]] && echo true || echo false)"

sign_in "$email_a" "$tmp_dir/session-a.json"
sign_in "$email_b" "$tmp_dir/session-b.json"
token_a=$(jq -r '.access_token // empty' "$tmp_dir/session-a.json")
token_b=$(jq -r '.access_token // empty' "$tmp_dir/session-b.json")
check_equal 'Hai user nhận session riêng' 'true' \
  "$([[ -n "$token_a" && -n "$token_b" && "$token_a" != "$token_b" ]] && echo true || echo false)"

anonymous_status=$(curl -sS -o "$tmp_dir/anonymous.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts?select=account_id" \
  -H "apikey: $PUBLISHABLE_KEY")
check_equal 'Anonymous không có quyền SELECT table' 'true' \
  "$([[ "$anonymous_status" == 401 || "$anonymous_status" == 403 ]] && echo true || echo false)"

insert_payload=$(jq -cn \
  --arg user_id "$user_a_id" \
  --arg account_id "$account_id" \
  '{
    user_id: $user_id,
    account_id: $account_id,
    issuer: "RLS contract test",
    account_name: "test@example.invalid",
    secret_key: "TEST_ONLY_NOT_A_SECRET",
    algorithm: "SHA256",
    digits: 8,
    period: 45
  }')

insert_status=$(curl -sS -o "$tmp_dir/insert-a.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts" \
  -X POST \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d "$insert_payload")
check_equal 'User A INSERT row của chính mình' '201' "$insert_status"
check_equal 'Mapper contract round-trip tham số TOTP' 'true' \
  "$(jq -r 'length == 1 and .[0].algorithm == "SHA256" and .[0].digits == 8 and .[0].period == 45' "$tmp_dir/insert-a.json")"

curl -fsS "$BASE_URL/rest/v1/synced_accounts?select=account_id&account_id=eq.$account_id" \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a" >"$tmp_dir/select-a.json"
curl -fsS "$BASE_URL/rest/v1/synced_accounts?select=account_id&account_id=eq.$account_id" \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_b" >"$tmp_dir/select-b.json"
check_equal 'User A SELECT được row của mình' '1' \
  "$(jq -r 'length' "$tmp_dir/select-a.json")"
check_equal 'User B không SELECT được row của User A' '0' \
  "$(jq -r 'length' "$tmp_dir/select-b.json")"

update_b_status=$(curl -sS -o "$tmp_dir/update-b.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts?account_id=eq.$account_id" \
  -X PATCH \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_b" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"period":60}')
check_equal 'User B UPDATE không tác động row của User A' '200' "$update_b_status"
check_equal 'User B UPDATE trả về 0 row' '0' \
  "$(jq -r 'length' "$tmp_dir/update-b.json")"

delete_b_status=$(curl -sS -o "$tmp_dir/delete-b.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts?account_id=eq.$account_id" \
  -X DELETE \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_b" \
  -H 'Prefer: return=representation')
check_equal 'User B DELETE không tác động row của User A' '200' "$delete_b_status"
check_equal 'User B DELETE trả về 0 row' '0' \
  "$(jq -r 'length' "$tmp_dir/delete-b.json")"

spoof_payload=$(jq -cn \
  --arg user_id "$user_a_id" \
  --arg account_id "$(make_uuid)" \
  '{
    user_id: $user_id,
    account_id: $account_id,
    issuer: "RLS spoof test",
    account_name: "test@example.invalid",
    secret_key: "TEST_ONLY_NOT_A_SECRET"
  }')
spoof_status=$(curl -sS -o "$tmp_dir/spoof.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts" \
  -X POST \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_b" \
  -H 'Content-Type: application/json' \
  -d "$spoof_payload")
check_equal 'User B không INSERT với owner là User A' 'true' \
  "$([[ "$spoof_status" == 401 || "$spoof_status" == 403 ]] && echo true || echo false)"

update_a_status=$(curl -sS -o "$tmp_dir/update-a.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts?account_id=eq.$account_id" \
  -X PATCH \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"period":60}')
check_equal 'User A UPDATE row của mình' '200' "$update_a_status"
check_equal 'User A UPDATE giữ owner và đổi period' 'true' \
  "$(jq -r --arg user_id "$user_a_id" 'length == 1 and .[0].user_id == $user_id and .[0].period == 60' "$tmp_dir/update-a.json")"

delete_a_status=$(curl -sS -o "$tmp_dir/delete-a.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/synced_accounts?account_id=eq.$account_id" \
  -X DELETE \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a" \
  -H 'Prefer: return=representation')
check_equal 'User A DELETE row của mình' '200' "$delete_a_status"
check_equal 'User A DELETE đúng một row' '1' \
  "$(jq -r 'length' "$tmp_dir/delete-a.json")"

curl -fsS "$BASE_URL/rest/v1/synced_accounts?select=account_id&account_id=eq.$account_id" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" >"$tmp_dir/final.json"
check_equal 'Dữ liệu test đã được dọn sạch' '0' \
  "$(jq -r 'length' "$tmp_dir/final.json")"

printf '\n=== Kết quả: %d pass, %d fail ===\n' "$pass" "$fail"
if ((fail > 0)); then
  exit 1
fi
