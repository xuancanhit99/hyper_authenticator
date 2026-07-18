#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${1:-.env}
BASE_URL=${2:-}
RECOVERY_URL=${3:-}

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
if [[ -z "$RECOVERY_URL" ]]; then
  RECOVERY_URL=$(read_env_value PASSWORD_RECOVERY_URL)
fi
PUBLISHABLE_KEY=$(first_env_value SUPABASE_PUBLISHABLE_KEY PUBLISHABLE_KEY ANON_KEY)
SERVICE_ROLE_KEY=$(read_env_value SERVICE_ROLE_KEY)

if [[ -z "$BASE_URL" || -z "$RECOVERY_URL" || -z "$PUBLISHABLE_KEY" || -z "$SERVICE_ROLE_KEY" ]]; then
  printf '%s\n' 'Thiếu public URL, recovery URL, publishable key hoặc service role operator key.' >&2
  exit 78
fi
if [[ "$RECOVERY_URL" != https://* ]]; then
  printf '%s\n' 'Recovery URL phải dùng HTTPS.' >&2
  exit 78
fi
BASE_URL=${BASE_URL%/}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-recovery-contract.XXXXXX")
chmod 700 "$tmp_dir"
user_id=
suffix="$(date +%s)-$$"
email="recovery-${suffix}@example.invalid"
old_password="TEST_ONLY-old-password-${suffix}"
new_password="TEST_ONLY-new-password-${suffix}"

cleanup() {
  if [[ -n "$user_id" ]]; then
    curl --max-time 15 -fsS -o /dev/null -X DELETE \
      "$BASE_URL/auth/v1/admin/users/$user_id" \
      -H "apikey: $SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SERVICE_ROLE_KEY" || true
  fi
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT INT TERM

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

jq -cn --arg email "$email" --arg password "$old_password" \
  '{email: $email, password: $password, email_confirm: true}' \
  | curl --max-time 15 -fsS "$BASE_URL/auth/v1/admin/users" -X POST \
      -H "apikey: $SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
      -H 'Content-Type: application/json' -d @- > "$tmp_dir/user.json"
user_id=$(jq -r '.id // empty' "$tmp_dir/user.json")
check 'Tạo isolated recovery user' test -n "$user_id"

jq -cn --arg email "$email" --arg redirect_to "$RECOVERY_URL" \
  '{type: "recovery", email: $email, redirect_to: $redirect_to}' \
  | curl --max-time 15 -fsS "$BASE_URL/auth/v1/admin/generate_link" -X POST \
      -H "apikey: $SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
      -H 'Content-Type: application/json' -d @- > "$tmp_dir/link.json"
token_hash=$(jq -r '.hashed_token // empty' "$tmp_dir/link.json")
check 'Generate one-time recovery token hash' test -n "$token_hash"
check 'Generate link giữ exact recovery redirect' jq -e \
  --arg redirect_to "$RECOVERY_URL" '.redirect_to == $redirect_to' \
  "$tmp_dir/link.json"

jq -cn --arg token_hash "$token_hash" \
  '{type: "recovery", token_hash: $token_hash}' \
  | curl --max-time 15 -fsS "$BASE_URL/auth/v1/verify" -X POST \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H 'Content-Type: application/json' -d @- > "$tmp_dir/session.json"
access_token=$(jq -r '.access_token // empty' "$tmp_dir/session.json")
check 'verifyOtp recovery tạo session' test -n "$access_token"

jq -cn --arg password "$new_password" '{password: $password}' \
  | curl --max-time 15 -fsS "$BASE_URL/auth/v1/user" -X PUT \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H "Authorization: Bearer $access_token" \
      -H 'Content-Type: application/json' -d @- > "$tmp_dir/update.json"
check 'Recovery session cập nhật mật khẩu' jq -e \
  --arg user_id "$user_id" '.id == $user_id' "$tmp_dir/update.json"

jq -cn --arg email "$email" --arg password "$new_password" \
  '{email: $email, password: $password}' \
  | curl --max-time 15 -fsS "$BASE_URL/auth/v1/token?grant_type=password" \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H 'Content-Type: application/json' -d @- > "$tmp_dir/sign-in.json"
check 'Đăng nhập được bằng mật khẩu mới' jq -e \
  '.access_token | type == "string" and length > 0' "$tmp_dir/sign-in.json"

reuse_status=$(jq -cn --arg token_hash "$token_hash" \
  '{type: "recovery", token_hash: $token_hash}' \
  | curl --max-time 15 -sS -o "$tmp_dir/reuse.json" -w '%{http_code}' \
      "$BASE_URL/auth/v1/verify" -X POST \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H 'Content-Type: application/json' -d @-)
check 'Recovery token không tái sử dụng được' test "$reuse_status" -ge 400

malformed_status=$(jq -cn \
  '{type: "recovery", token_hash: "TOKEN_HASH_TEST_ONLY_MALFORMED"}' \
  | curl --max-time 15 -sS -o "$tmp_dir/malformed.json" -w '%{http_code}' \
      "$BASE_URL/auth/v1/verify" -X POST \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H 'Content-Type: application/json' -d @-)
check 'Malformed recovery token bị từ chối' test "$malformed_status" -ge 400

printf 'Remote recovery contract pass: %s checks.\n' "$pass"
