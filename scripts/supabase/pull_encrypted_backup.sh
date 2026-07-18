#!/usr/bin/env bash
set -euo pipefail

OPERATOR_ENV=${OPERATOR_ENV:?Cần trỏ OPERATOR_ENV tới file chứa SSH config.}
AGE_RECIPIENT_FILE=${AGE_RECIPIENT_FILE:?Cần AGE_RECIPIENT_FILE.}
AGE_IDENTITY_FILE=${AGE_IDENTITY_FILE:-}
DESTINATION_ROOT=${DESTINATION_ROOT:-"$HOME/Backups/hyper_authenticator/supabase-production-encrypted"}
REMOTE_BACKUP_ROOT=${REMOTE_BACKUP_ROOT:-/home/xuancanhit/backups/hyper-authenticator/scheduled}
RETENTION_COUNT=${RETENTION_COUNT:-14}

read_env_value() {
  local key_name=$1
  local key_line value
  key_line=$(grep -m1 "^${key_name}=" "$OPERATOR_ENV" || true)
  [[ -n "$key_line" ]] || return 1
  value=${key_line#*=}
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value=${value:1:${#value}-2}
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

REMOTE_HOST=$(read_env_value REMOTE_HOST)
REMOTE_PORT=$(read_env_value REMOTE_PORT)
REMOTE_USER=$(read_env_value REMOTE_USER)
SSH_KEY_PATH=$(read_env_value SSH_KEY_PATH)
recipient=$(grep -m1 '^age1' "$AGE_RECIPIENT_FILE")

[[ -n "$REMOTE_HOST" && -n "$REMOTE_PORT" && -n "$REMOTE_USER" ]]
[[ -f "$SSH_KEY_PATH" && -n "$recipient" ]]

umask 077
mkdir -p "$DESTINATION_ROOT"
chmod 700 "$DESTINATION_ROOT"
lock_dir="$DESTINATION_ROOT/.pull.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf '%s\n' 'Một encrypted off-host backup khác đang chạy.' >&2
  exit 75
fi
cleanup() {
  rm -rf "$lock_dir"
  [[ -z "${temporary_output:-}" ]] || rm -f "$temporary_output"
}
trap cleanup EXIT INT TERM

ssh_options=(
  -i "$SSH_KEY_PATH"
  -p "$REMOTE_PORT"
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o StrictHostKeyChecking=yes
)
remote_target="$REMOTE_USER@$REMOTE_HOST"

latest_backup=$(ssh "${ssh_options[@]}" "$remote_target" \
  "find '$REMOTE_BACKUP_ROOT' -mindepth 1 -maxdepth 1 -type d -name 'supabase-*' -printf '%f\\n' | sort | tail -1")
[[ "$latest_backup" =~ ^supabase-[0-9]{8}T[0-9]{6}Z$ ]]

output_name="$latest_backup.tar.gz.age"
final_output="$DESTINATION_ROOT/$output_name"
if [[ ! -f "$final_output" ]]; then
  temporary_output=$(mktemp "$DESTINATION_ROOT/.${output_name}.XXXXXX")
  ssh "${ssh_options[@]}" "$remote_target" \
    "tar -C '$REMOTE_BACKUP_ROOT' -czf - '$latest_backup'" \
    | age -r "$recipient" -o "$temporary_output"
  chmod 600 "$temporary_output"
  mv "$temporary_output" "$final_output"
  temporary_output=''
fi

(
  cd "$DESTINATION_ROOT"
  shasum -a 256 "$output_name" >"$output_name.sha256"
  shasum -a 256 -c "$output_name.sha256" >/dev/null
)

if [[ -n "$AGE_IDENTITY_FILE" ]]; then
  [[ -f "$AGE_IDENTITY_FILE" ]]
  age -d -i "$AGE_IDENTITY_FILE" "$final_output" | tar -tzf - >/dev/null
fi

index=0
while IFS= read -r backup_path; do
  index=$((index + 1))
  if ((index > RETENTION_COUNT)); then
    rm -f -- "$backup_path" "$backup_path.sha256"
  fi
done < <(find "$DESTINATION_ROOT" -maxdepth 1 -type f \
  -name 'supabase-*.tar.gz.age' | sort -r)

printf 'Encrypted off-host backup pass: %s\n' "$final_output"
