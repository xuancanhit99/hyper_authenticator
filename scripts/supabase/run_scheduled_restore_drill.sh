#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BACKUP_ROOT=${BACKUP_ROOT:-/home/xuancanhit/backups/hyper-authenticator/scheduled}
BACKUP_ROOT=${BACKUP_ROOT%/}
RESTORE_DRILL_STATE_DIR=${RESTORE_DRILL_STATE_DIR:-$BACKUP_ROOT/.restore-drill}
RESTORE_DRILL_STATE_DIR=${RESTORE_DRILL_STATE_DIR%/}
RESTORE_DRILL_STATE_FILE=${RESTORE_DRILL_STATE_FILE:-$RESTORE_DRILL_STATE_DIR/last-success.env}
RESTORE_REHEARSAL_SCRIPT=${RESTORE_REHEARSAL_SCRIPT:-$SCRIPT_DIR/rehearse_backup_restore.sh}
RESTORE_STATE_CHECK_SCRIPT=${RESTORE_STATE_CHECK_SCRIPT:-$SCRIPT_DIR/check_restore_drill_state.sh}
MIN_RESTORE_INTERVAL_SECONDS=${MIN_RESTORE_INTERVAL_SECONDS:-604800}
MAX_BACKUP_AGE_SECONDS=${MAX_BACKUP_AGE_SECONDS:-129600}

fail() {
  printf 'Scheduled restore drill thất bại: %s\n' "$1" >&2
  exit 1
}

[[ "$MIN_RESTORE_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || fail 'minimum interval không hợp lệ.'
[[ "$MAX_BACKUP_AGE_SECONDS" =~ ^[0-9]+$ ]] || fail 'backup max age không hợp lệ.'
[[ -n "$BACKUP_ROOT" && -n "$RESTORE_DRILL_STATE_DIR" ]] || fail 'path cấu hình rỗng.'
[[ -d "$BACKUP_ROOT" && ! -L "$BACKUP_ROOT" ]] || fail 'backup root thiếu hoặc là symlink.'
[[ -x "$RESTORE_REHEARSAL_SCRIPT" ]] || fail 'restore rehearsal script không executable.'
[[ -x "$RESTORE_STATE_CHECK_SCRIPT" ]] || fail 'state checker không executable.'
command -v flock >/dev/null 2>&1 || fail 'thiếu flock.'

umask 077
mkdir -p "$RESTORE_DRILL_STATE_DIR"
[[ -d "$RESTORE_DRILL_STATE_DIR" && ! -L "$RESTORE_DRILL_STATE_DIR" ]] || \
  fail 'state directory không hợp lệ hoặc là symlink.'
chmod 700 "$RESTORE_DRILL_STATE_DIR"

exec 8>"$RESTORE_DRILL_STATE_DIR/.scheduled-restore.lock"
if ! flock -n 8; then
  printf '%s\n' 'Scheduled restore drill khác đang chạy; không tạo lượt trùng.'
  exit 0
fi

if "$RESTORE_STATE_CHECK_SCRIPT" \
  "$RESTORE_DRILL_STATE_FILE" "$MIN_RESTORE_INTERVAL_SECONDS" \
  >/dev/null 2>&1; then
  printf '%s\n' 'Scheduled restore drill chưa tới hạn; giữ evidence hiện tại.'
  exit 0
fi

latest_backup=''
while IFS= read -r candidate; do
  latest_backup=$candidate
done < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name 'supabase-*' -print | LC_ALL=C sort
)
[[ -n "$latest_backup" ]] || fail 'không tìm thấy backup hoàn chỉnh.'

backup_name=$(basename "$latest_backup")
[[ "$backup_name" =~ ^supabase-[0-9]{8}T[0-9]{6}Z$ ]] || \
  fail 'tên backup mới nhất không hợp lệ.'
[[ "$latest_backup" == "$BACKUP_ROOT/$backup_name" ]] || fail 'backup path không canonical.'
[[ -f "$latest_backup/manifest.txt" && ! -L "$latest_backup/manifest.txt" ]] || \
  fail 'backup manifest thiếu hoặc là symlink.'

backup_stamp=${backup_name#supabase-}
backup_iso="${backup_stamp:0:4}-${backup_stamp:4:2}-${backup_stamp:6:2}T${backup_stamp:9:2}:${backup_stamp:11:2}:${backup_stamp:13:2}Z"
if backup_epoch=$(date -u -d "$backup_iso" +%s 2>/dev/null); then
  :
elif backup_epoch=$(date -j -u -f '%Y%m%dT%H%M%SZ' "$backup_stamp" +%s 2>/dev/null); then
  :
else
  fail 'không parse được timestamp backup.'
fi
now_epoch=$(date +%s)
((backup_epoch <= now_epoch)) || fail 'backup timestamp nằm trong tương lai.'
backup_age=$((now_epoch - backup_epoch))
((backup_age <= MAX_BACKUP_AGE_SECONDS)) || fail 'backup mới nhất đã quá hạn.'

"$RESTORE_REHEARSAL_SCRIPT" "$latest_backup"

if command -v sha256sum >/dev/null 2>&1; then
  manifest_sha256=$(sha256sum "$latest_backup/manifest.txt" | awk '{print $1}')
else
  manifest_sha256=$(shasum -a 256 "$latest_backup/manifest.txt" | awk '{print $1}')
fi
[[ "$manifest_sha256" =~ ^[0-9a-f]{64}$ ]] || fail 'không tính được manifest checksum.'

completed_epoch=$(date +%s)
completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
state_tmp=$(mktemp "$RESTORE_DRILL_STATE_DIR/.last-success.XXXXXX")
cleanup_state_tmp() {
  rm -f -- "$state_tmp"
}
trap cleanup_state_tmp EXIT INT TERM

cat >"$state_tmp" <<EOF
format_version=1
completed_at_epoch=$completed_epoch
completed_at_utc=$completed_utc
backup_name=$backup_name
backup_manifest_sha256=$manifest_sha256
EOF
chmod 600 "$state_tmp"
mv -f "$state_tmp" "$RESTORE_DRILL_STATE_FILE"
trap - EXIT INT TERM

"$RESTORE_STATE_CHECK_SCRIPT" "$RESTORE_DRILL_STATE_FILE" 60 >/dev/null
printf 'Scheduled restore drill pass: %s.\n' "$backup_name"
