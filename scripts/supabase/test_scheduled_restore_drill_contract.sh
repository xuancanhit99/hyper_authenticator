#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RUNNER="$ROOT/scripts/supabase/run_scheduled_restore_drill.sh"
STATE_CHECKER="$ROOT/scripts/supabase/check_restore_drill_state.sh"
REHEARSAL="$ROOT/scripts/supabase/rehearse_backup_restore.sh"
HEALTH="$ROOT/scripts/supabase/check_production_health.sh"
SERVICE="$ROOT/supabase/systemd/hyper-auth-supabase-restore-drill.service"
TIMER="$ROOT/supabase/systemd/hyper-auth-supabase-restore-drill.timer"

bash -n "$RUNNER" "$STATE_CHECKER" "$REHEARSAL" "$HEALTH"

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ha-restore-drill-contract.XXXXXX")
cleanup() {
  rm -rf -- "$temp_dir"
}
trap cleanup EXIT INT TERM

backup_root="$temp_dir/backups"
state_dir="$backup_root/.restore-drill"
state_file="$state_dir/last-success.env"
fake_bin="$temp_dir/bin"
calls_file="$temp_dir/rehearsal-calls"
mkdir -p "$backup_root" "$fake_bin"

cat >"$fake_bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$temp_dir/fake-rehearsal.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -d "${1:?missing backup}" ]]
printf '%s\n' "$(basename "$1")" >>"${RESTORE_CALLS_FILE:?}"
[[ "${RESTORE_STUB_FAIL:-false}" != true ]]
EOF
chmod 700 "$fake_bin/flock" "$temp_dir/fake-rehearsal.sh"

current_backup="$backup_root/supabase-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$current_backup"
printf '%s\n' 'TEST_ONLY restore manifest' >"$current_backup/manifest.txt"

runner_env=(
  env
  "PATH=$fake_bin:$PATH"
  "BACKUP_ROOT=$backup_root"
  "RESTORE_DRILL_STATE_DIR=$state_dir"
  "RESTORE_DRILL_STATE_FILE=$state_file"
  "RESTORE_REHEARSAL_SCRIPT=$temp_dir/fake-rehearsal.sh"
  "RESTORE_STATE_CHECK_SCRIPT=$STATE_CHECKER"
  'MIN_RESTORE_INTERVAL_SECONDS=604800'
  'MAX_BACKUP_AGE_SECONDS=60'
  "RESTORE_CALLS_FILE=$calls_file"
)

"${runner_env[@]}" "$RUNNER" >/dev/null
[[ -f "$state_file" && ! -L "$state_file" ]]
"$STATE_CHECKER" "$state_file" 60 >/dev/null
[[ $(wc -l <"$calls_file" | tr -d ' ') == 1 ]]
grep -qx "backup_name=$(basename "$current_backup")" "$state_file"

if mode=$(stat -c '%a' "$state_file" 2>/dev/null); then
  :
else
  mode=$(stat -f '%Lp' "$state_file")
fi
[[ "$mode" == 600 ]]

"${runner_env[@]}" "$RUNNER" >/dev/null
[[ $(wc -l <"$calls_file" | tr -d ' ') == 1 ]]

now_epoch=$(date +%s)
manifest_sha=$(awk -F= '$1 == "backup_manifest_sha256" { print $2 }' "$state_file")
cat >"$state_file" <<EOF
format_version=1
completed_at_epoch=$((now_epoch - 60))
completed_at_utc=2000-01-01T00:00:00Z
backup_name=$(basename "$current_backup")
backup_manifest_sha256=$manifest_sha
EOF
chmod 600 "$state_file"
cp "$state_file" "$temp_dir/state-before-failure"

if env "${runner_env[@]:1}" \
  MIN_RESTORE_INTERVAL_SECONDS=1 RESTORE_STUB_FAIL=true \
  "$RUNNER" >/dev/null 2>&1; then
  printf '%s\n' 'Restore rehearsal failure phải làm scheduled runner fail.' >&2
  exit 1
fi
cmp -s "$state_file" "$temp_dir/state-before-failure"

chmod 644 "$state_file"
if "$STATE_CHECKER" "$state_file" 600 >/dev/null 2>&1; then
  printf '%s\n' 'Evidence mode rộng phải bị từ chối.' >&2
  exit 1
fi
chmod 600 "$state_file"

sed 's/^format_version=.*/format_version=99/' "$state_file" \
  >"$temp_dir/invalid-state"
chmod 600 "$temp_dir/invalid-state"
if "$STATE_CHECKER" "$temp_dir/invalid-state" 600 >/dev/null 2>&1; then
  printf '%s\n' 'Unknown evidence format phải bị từ chối.' >&2
  exit 1
fi

rm -f "$state_file"
rm -rf "$current_backup"
stale_backup="$backup_root/supabase-20000101T000000Z"
mkdir -p "$stale_backup"
printf '%s\n' 'TEST_ONLY stale manifest' >"$stale_backup/manifest.txt"
if "${runner_env[@]}" MAX_BACKUP_AGE_SECONDS=1 "$RUNNER" >/dev/null 2>&1; then
  printf '%s\n' 'Backup quá hạn phải bị từ chối.' >&2
  exit 1
fi
[[ ! -e "$state_file" ]]

grep -Fq 'flock -n 9' "$REHEARSAL"
grep -Fq 'check_restore_drill_state.sh' "$HEALTH"
grep -Fq 'TimeoutStartSec=2h' "$SERVICE"
grep -Fq 'ReadWritePaths=/home/xuancanhit/backups/hyper-authenticator' "$SERVICE"
grep -Fq 'OnCalendar=*-*-* 04:30:00 UTC' "$TIMER"
grep -Fq 'Persistent=true' "$TIMER"

printf '%s\n' \
  'Scheduled restore drill contract pass: due/skip/failure/stale/state-mode/systemd.'
