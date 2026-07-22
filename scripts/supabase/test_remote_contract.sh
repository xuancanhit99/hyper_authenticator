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

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-plaintext-retired.XXXXXX")
chmod 700 "$tmp_dir"
trap 'find "$tmp_dir" -depth -delete' EXIT

endpoint="${BASE_URL%/}/rest/v1/synced_accounts?select=account_id&limit=1"

request_status() {
  local name=$1
  local apikey=$2
  local bearer=$3
  local output="$tmp_dir/$name.json"
  curl --proto '=https' --tlsv1.2 --silent --show-error \
    --connect-timeout 10 --max-time 20 \
    --output "$output" --write-out '%{http_code}' \
    -H "apikey: $apikey" \
    -H "Authorization: Bearer $bearer" \
    "$endpoint"
}

public_status=$(request_status public "$PUBLISHABLE_KEY" "$PUBLISHABLE_KEY")
service_status=$(request_status service "$SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY")

if [[ "$public_status" != 404 || "$service_status" != 404 ]]; then
  printf '%s\n' \
    'Plaintext endpoint vẫn tồn tại hoặc PostgREST schema cache chưa reload.' >&2
  printf 'HTTP status public/service: %s/%s\n' \
    "$public_status" "$service_status" >&2
  exit 1
fi

for response in "$tmp_dir/public.json" "$tmp_dir/service.json"; do
  if ! jq -e '
    (.code == "PGRST205" or .code == "42P01") and
    ((.message // "") | contains("synced_accounts"))
  ' "$response" >/dev/null; then
    printf '%s\n' \
      'Remote không trả contract table-absent mong đợi cho synced_accounts.' >&2
    exit 1
  fi
done

printf '%s\n' \
  'Supabase plaintext retirement contract pass: public và service role đều nhận table-absent.'
