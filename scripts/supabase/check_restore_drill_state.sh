#!/usr/bin/env bash
set -euo pipefail

STATE_FILE=${1:?Usage: check_restore_drill_state.sh STATE_FILE MAX_AGE_SECONDS}
MAX_AGE_SECONDS=${2:?Usage: check_restore_drill_state.sh STATE_FILE MAX_AGE_SECONDS}

fail() {
  printf 'Restore drill evidence không hợp lệ: %s\n' "$1" >&2
  exit 1
}

[[ "$MAX_AGE_SECONDS" =~ ^[0-9]+$ ]] || fail 'max age không phải số nguyên.'
[[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || fail 'file thiếu hoặc là symlink.'

if mode=$(stat -c '%a' "$STATE_FILE" 2>/dev/null); then
  :
elif mode=$(stat -f '%Lp' "$STATE_FILE" 2>/dev/null); then
  :
else
  fail 'không đọc được file mode.'
fi
[[ "$mode" == 600 ]] || fail 'file mode phải là 0600.'

line_count=$(awk 'END { print NR }' "$STATE_FILE")
[[ "$line_count" == 5 ]] || fail 'evidence phải có đúng 5 field.'

while IFS= read -r line; do
  case "$line" in
    format_version=* | completed_at_epoch=* | completed_at_utc=* | \
      backup_name=* | backup_manifest_sha256=*) ;;
    *) fail 'có field lạ hoặc dòng trống.' ;;
  esac
done <"$STATE_FILE"

read_field() {
  local key=$1
  awk -F= -v key="$key" '
    $1 == key {
      count += 1
      value = substr($0, index($0, "=") + 1)
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' "$STATE_FILE"
}

format_version=$(read_field format_version) || fail 'format_version thiếu hoặc lặp.'
completed_at_epoch=$(read_field completed_at_epoch) || fail 'completed_at_epoch thiếu hoặc lặp.'
completed_at_utc=$(read_field completed_at_utc) || fail 'completed_at_utc thiếu hoặc lặp.'
backup_name=$(read_field backup_name) || fail 'backup_name thiếu hoặc lặp.'
manifest_sha256=$(read_field backup_manifest_sha256) || fail 'manifest checksum thiếu hoặc lặp.'

[[ "$format_version" == 1 ]] || fail 'format version chưa được hỗ trợ.'
[[ "$completed_at_epoch" =~ ^[0-9]+$ ]] || fail 'completed_at_epoch không hợp lệ.'
[[ "$completed_at_utc" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || \
  fail 'completed_at_utc không hợp lệ.'
[[ "$backup_name" =~ ^supabase-[0-9]{8}T[0-9]{6}Z$ ]] || \
  fail 'backup_name không hợp lệ.'
[[ "$manifest_sha256" =~ ^[0-9a-f]{64}$ ]] || \
  fail 'backup manifest checksum không hợp lệ.'

now_epoch=$(date +%s)
((completed_at_epoch <= now_epoch)) || fail 'timestamp nằm trong tương lai.'
age_seconds=$((now_epoch - completed_at_epoch))
((age_seconds <= MAX_AGE_SECONDS)) || fail 'evidence đã quá hạn.'

printf 'Restore drill evidence pass: %s, age %s giây.\n' \
  "$backup_name" "$age_seconds"
