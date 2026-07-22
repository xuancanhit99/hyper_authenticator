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
installation_a='10000000-0000-4000-8000-000000000001'

# Canonical padded base64url test vectors. Chúng hoàn toàn tổng hợp, không dẫn
# xuất từ credential thật và chỉ gắn với isolated contract user được cleanup.
zero_32='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
one_32='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
two_32='AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI='
three_32='AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM='
zero_16='AAAAAAAAAAAAAAAAAAAAAA=='

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
  local ciphertext=${5:-TEST_ONLY_CIPHERTEXT_REVISION_1}
  jq -cn \
    --argjson expected "$expected_revision" \
    --arg wrapped_key_ciphertext "$wrapped_key_ciphertext" \
    --arg ciphertext "$ciphertext" '{
    p_expected_revision: $expected,
    p_format_version: 1,
    p_cipher: "AES-256-GCM",
    p_nonce: "AAAAAAAAAAAAAAAA",
    p_ciphertext: $ciphertext,
    p_auth_tag: "AAAAAAAAAAAAAAAAAAAAAA==",
    p_key_format_version: 1,
    p_wrapped_key_nonce: "BBBBBBBBBBBBBBBB",
    p_wrapped_key_ciphertext: $wrapped_key_ciphertext,
    p_wrapped_key_auth_tag: "BBBBBBBBBBBBBBBBBBBBBB=="
  }' | \
    curl --max-time 15 -sS -o "$output" -w '%{http_code}' \
      "$BASE_URL/rest/v1/rpc/publish_encrypted_vault_snapshot" -X POST \
      -H "apikey: $PUBLISHABLE_KEY" \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' -d @-
}

rpc() {
  local function_name=$1
  local token=$2
  local payload=$3
  local output=$4
  curl --max-time 15 -sS -o "$output" -w '%{http_code}' \
    "$BASE_URL/rest/v1/rpc/$function_name" -X POST \
    -H "apikey: $PUBLISHABLE_KEY" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' -d "$payload"
}

publish_v2() {
  local token=$1
  local expected_revision=$2
  local expected_generation=$3
  local binding_secret=$4
  local output=$5
  local wrapped_key_ciphertext=${6:-TEST_ONLY_ROTATED_WRAPPED_KEY_CIPHERTEXT_123456}
  local ciphertext=${7:-TEST_ONLY_CIPHERTEXT_REVISION_2_WITH_NEW_DEK}
  local payload
  payload=$(jq -cn \
    --argjson expected_revision "$expected_revision" \
    --argjson expected_generation "$expected_generation" \
    --arg binding_secret "$binding_secret" \
    --arg wrapped_key_ciphertext "$wrapped_key_ciphertext" \
    --arg ciphertext "$ciphertext" '{
      p_expected_revision: $expected_revision,
      p_expected_key_generation: $expected_generation,
      p_current_binding_secret: $binding_secret,
      p_format_version: 1,
      p_cipher: "AES-256-GCM",
      p_nonce: "AAAAAAAAAAAAAAAA",
      p_ciphertext: $ciphertext,
      p_auth_tag: "AAAAAAAAAAAAAAAAAAAAAA==",
      p_key_format_version: 1,
      p_wrapped_key_nonce: "BBBBBBBBBBBBBBBB",
      p_wrapped_key_ciphertext: $wrapped_key_ciphertext,
      p_wrapped_key_auth_tag: "BBBBBBBBBBBBBBBBBBBBBB=="
    }')
  rpc publish_encrypted_vault_snapshot_v2 "$token" "$payload" "$output"
}

register_native_device() {
  local token=$1
  local output=$2
  local payload
  payload=$(jq -cn --arg installation_id "$installation_a" '{
    p_installation_id: $installation_id,
    p_display_name: "Hyper Authenticator contract device",
    p_platform: "linux"
  }')
  rpc register_current_authenticator_device "$token" "$payload" "$output"
}

begin_device_key_enrollment() {
  local token=$1
  local output=$2
  local payload
  payload=$(jq -cn \
    --arg installation_id "$installation_a" \
    --arg public_key "$zero_32" \
    --arg binding_secret "$one_32" \
    --arg membership_verifier "$three_32" '{
      p_installation_id: $installation_id,
      p_public_key: $public_key,
      p_binding_secret: $binding_secret,
      p_vault_membership_verifier: $membership_verifier
    }')
  rpc begin_authenticator_device_key_enrollment "$token" "$payload" "$output"
}

publish_self_wrap() {
  local token=$1
  local device_key_id=$2
  local output=$3
  local payload
  payload=$(jq -cn \
    --arg device_key_id "$device_key_id" \
    --arg binding_secret "$one_32" \
    --arg encapsulated_key "$one_32" \
    --arg ciphertext "$two_32" \
    --arg auth_tag "$zero_16" \
    --arg membership_verifier "$three_32" \
    --arg membership_proof "$three_32" '{
      p_target_device_key_id: $device_key_id,
      p_current_binding_secret: $binding_secret,
      p_expected_key_generation: 1,
      p_format_version: 1,
      p_kem: "DHKEM-X25519-HKDF-SHA256",
      p_kdf: "HKDF-SHA256",
      p_aead: "AES-256-GCM",
      p_encapsulated_key: $encapsulated_key,
      p_ciphertext: $ciphertext,
      p_auth_tag: $auth_tag,
      p_vault_membership_verifier: $membership_verifier,
      p_membership_proof: $membership_proof
    }')
  rpc publish_authenticator_device_key_wrap "$token" "$payload" "$output"
}

confirm_device_key() {
  local token=$1
  local device_key_id=$2
  local output=$3
  local payload
  payload=$(jq -cn \
    --arg device_key_id "$device_key_id" \
    --arg binding_secret "$one_32" '{
      p_device_key_id: $device_key_id,
      p_binding_secret: $binding_secret,
      p_expected_key_generation: 1
    }')
  rpc confirm_current_authenticator_device_key "$token" "$payload" "$output"
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

is_success_status() {
  (( $1 >= 200 && $1 < 300 ))
}

is_client_error_status() {
  (( $1 >= 400 && $1 < 500 ))
}

is_error_status() {
  (( $1 >= 400 && $1 < 600 ))
}

sessions_ready() {
  [[ -n "$user_a_id" && -n "$user_b_id" && -n "$token_a" &&
    -n "$token_a_old" && -n "$refresh_token_a_old" && -n "$token_b" &&
    "$token_a" != "$token_a_old" ]]
}

create_user "$email_a" "$tmp_dir/user-a.json"
create_user "$email_b" "$tmp_dir/user-b.json"
user_a_id=$(jq -r '.id // empty' "$tmp_dir/user-a.json")
user_b_id=$(jq -r '.id // empty' "$tmp_dir/user-b.json")
sign_in "$email_a" "$tmp_dir/session-a-old.json"
sign_in "$email_a" "$tmp_dir/session-a.json"
sign_in "$email_b" "$tmp_dir/session-b.json"
token_a_old=$(jq -r '.access_token // empty' "$tmp_dir/session-a-old.json")
refresh_token_a_old=$(jq -r \
  '.refresh_token // empty' "$tmp_dir/session-a-old.json")
token_a=$(jq -r '.access_token // empty' "$tmp_dir/session-a.json")
token_b=$(jq -r '.access_token // empty' "$tmp_dir/session-b.json")
check 'Tạo hai user và hai session riêng cho User A' sessions_ready

anonymous_status=$(curl --max-time 15 -sS -o "$tmp_dir/anonymous.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision" \
  -H "apikey: $PUBLISHABLE_KEY")
check 'Anonymous không SELECT encrypted table' test "$anonymous_status" -ge 400

first_status=$(publish "$token_a" 0 "$tmp_dir/publish-1.json")
check 'User A publish revision đầu' test "$first_status" -eq 200
check 'Server trả revision 1' jq -e 'length == 1 and .[0].revision == 1' \
  "$tmp_dir/publish-1.json"

null_revision_status=$(publish \
  "$token_b" null "$tmp_dir/null-expected-revision.json")
check 'Legacy RPC từ chối expected revision NULL' sh -c \
  'test "$1" -ge 400 && jq -e '\''(.message // "") | contains("invalid_expected_revision")'\'' "$2" >/dev/null' \
  sh "$null_revision_status" "$tmp_dir/null-expected-revision.json"

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

rotated_wrapped_key='TEST_ONLY_ROTATED_WRAPPED_KEY_CIPHERTEXT_123456'
rotated_ciphertext='TEST_ONLY_CIPHERTEXT_REVISION_2_WITH_NEW_DEK'

legacy_cutoff_status=$(publish \
  "$token_a" 1 "$tmp_dir/legacy-revision-2.json" "$rotated_wrapped_key" \
  "$rotated_ciphertext")
check 'Legacy RPC không được publish revision 2' \
  is_error_status "$legacy_cutoff_status"
check 'Legacy cutoff trả device_key_protocol_required' jq -e \
  '(.message // "") | contains("device_key_protocol_required")' \
  "$tmp_dir/legacy-revision-2.json"

register_status=$(register_native_device "$token_a" \
  "$tmp_dir/register-current-device.json")
check 'Current session đăng ký native device' is_success_status "$register_status"
check 'Device registry trả opaque registration ID' jq -e \
  'length == 1 and (.[0].registration_id | type == "string")' \
  "$tmp_dir/register-current-device.json"

begin_status=$(begin_device_key_enrollment "$token_a" \
  "$tmp_dir/begin-device-key.json")
check 'Current native device bắt đầu enrollment' is_success_status "$begin_status"
check 'Enrollment ở generation 1 và trạng thái pending' jq -e \
  'length == 1 and .[0].device_state == "pending" and
   .[0].key_generation == 1 and (.[0].device_key_id | type == "string")' \
  "$tmp_dir/begin-device-key.json"
device_key_id=$(jq -r '.[0].device_key_id // empty' \
  "$tmp_dir/begin-device-key.json")
check 'Enrollment trả device key ID' test -n "$device_key_id"

wrap_status=$(publish_self_wrap "$token_a" "$device_key_id" \
  "$tmp_dir/publish-self-wrap.json")
check 'Current device publish self-wrap generation 1' \
  is_success_status "$wrap_status"
check 'Self-wrap RPC xác nhận true' jq -e '. == true' \
  "$tmp_dir/publish-self-wrap.json"

confirm_status=$(confirm_device_key "$token_a" "$device_key_id" \
  "$tmp_dir/confirm-device-key.json")
check 'Current device confirm wrap và bật protocol 1' \
  is_success_status "$confirm_status"
check 'Confirm RPC xác nhận true' jq -e '. == true' \
  "$tmp_dir/confirm-device-key.json"

second_status=$(publish_v2 \
  "$token_a" 1 1 "$one_32" "$tmp_dir/publish-2.json" \
  "$rotated_wrapped_key" "$rotated_ciphertext")
check 'Device-bound v2 publish revision 2' test "$second_status" -eq 200
check 'Server trả revision 2, generation 1 và protocol 1' jq -e \
  'length == 1 and .[0].revision == 2 and
   .[0].key_generation == 1 and .[0].device_wrap_version == 1' \
  "$tmp_dir/publish-2.json"

curl --max-time 15 -fsS \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision,key_generation,device_wrap_version,ciphertext,wrapped_key_ciphertext" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_a" \
  >"$tmp_dir/select-rotated-key.json"
check 'Revision mới atomically thay ciphertext và wrapped key' jq -e \
  --arg wrapped_key "$rotated_wrapped_key" \
  --arg ciphertext "$rotated_ciphertext" \
  'length == 1 and .[0].revision == 2 and
   .[0].key_generation == 1 and .[0].device_wrap_version == 1 and
   .[0].ciphertext == $ciphertext and
   .[0].wrapped_key_ciphertext == $wrapped_key' \
  "$tmp_dir/select-rotated-key.json"

stale_v2_status=$(publish_v2 \
  "$token_a" 1 1 "$one_32" "$tmp_dir/stale-v2.json")
check 'V2 stale revision trả HTTP 409' test "$stale_v2_status" -eq 409
check 'V2 conflict không trả encrypted payload' jq -e \
  '(.message // "") | contains("revision_or_generation_conflict")' \
  "$tmp_dir/stale-v2.json"

stale_initial_status=$(publish "$token_a" 0 "$tmp_dir/stale-initial.json")
check 'Initial RPC không overwrite row hiện có' test "$stale_initial_status" -eq 409
check 'Initial conflict không trả encrypted payload' jq -e \
  '(.message // "") | contains("revision_conflict")' \
  "$tmp_dir/stale-initial.json"

curl --max-time 15 -fsS \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_a_old" \
  >"$tmp_dir/select-a-old-before-revoke.json"
check 'Session cũ User A đọc được vault trước revoke' jq -e \
  'length == 1 and .[0].revision == 2' \
  "$tmp_dir/select-a-old-before-revoke.json"

revoke_status=$(curl --max-time 15 -sS \
  -o "$tmp_dir/revoke-other-sessions.json" -w '%{http_code}' \
  "$BASE_URL/auth/v1/logout?scope=others" -X POST \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a")
check 'Revoke tất cả session khác giữ session hiện tại' \
  is_success_status "$revoke_status"

old_refresh_status=$(jq -cn --arg refresh_token "$refresh_token_a_old" \
  '{refresh_token: $refresh_token}' | curl --max-time 15 -sS \
    -o "$tmp_dir/refresh-a-old-after-revoke.json" -w '%{http_code}' \
    "$BASE_URL/auth/v1/token?grant_type=refresh_token" -X POST \
    -H "apikey: $PUBLISHABLE_KEY" -H 'Content-Type: application/json' -d @-)
check 'Refresh token session cũ bị hủy' \
  is_client_error_status "$old_refresh_status"

old_select_status=$(curl --max-time 15 -sS \
  -o "$tmp_dir/select-a-old-after-revoke.json" -w '%{http_code}' \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision" \
  -H "apikey: $PUBLISHABLE_KEY" \
  -H "Authorization: Bearer $token_a_old")
check 'JWT session cũ còn parse được trong thời hạn' test \
  "$old_select_status" -eq 200
check 'RLS chặn session đã revoke đọc encrypted vault ngay' jq -e \
  'length == 0' "$tmp_dir/select-a-old-after-revoke.json"

old_publish_status=$(publish_v2 \
  "$token_a_old" 2 1 "$one_32" "$tmp_dir/publish-old-after-revoke.json")
check 'V2 RPC chặn session đã revoke publish ngay' test \
  "$old_publish_status" -eq 403
check 'RPC trả session_revoked không kèm encrypted payload' jq -e \
  '(.message // "") | contains("session_revoked")' \
  "$tmp_dir/publish-old-after-revoke.json"

curl --max-time 15 -fsS \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_a" \
  >"$tmp_dir/select-a-current-after-revoke.json"
check 'Session hiện tại vẫn đọc được encrypted vault' jq -e \
  'length == 1 and .[0].revision == 2' \
  "$tmp_dir/select-a-current-after-revoke.json"

spoof_status=$(publish_v2 \
  "$token_b" 2 1 "$one_32" "$tmp_dir/spoof.json")
check 'User B không update row User A qua v2 RPC' test "$spoof_status" -eq 409
check 'Cross-tenant v2 không tìm thấy revision/generation của User A' jq -e \
  '(.message // "") | contains("revision_or_generation_conflict")' \
  "$tmp_dir/spoof.json"

curl --max-time 15 -fsS \
  "$BASE_URL/rest/v1/encrypted_vault_snapshots?select=revision,ciphertext" \
  -H "apikey: $PUBLISHABLE_KEY" -H "Authorization: Bearer $token_a" \
  >"$tmp_dir/select-a-after-spoof.json"
check 'Cross-tenant attempt không mutate vault User A' jq -e \
  --arg ciphertext "$rotated_ciphertext" \
  'length == 1 and .[0].revision == 2 and .[0].ciphertext == $ciphertext' \
  "$tmp_dir/select-a-after-spoof.json"

printf 'Encrypted remote contract pass: %s checks.\n' "$pass"
