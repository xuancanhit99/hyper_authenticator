#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR=${COMPOSE_DIR:-/opt/stacks/supabase}
BACKUP_ROOT=${BACKUP_ROOT:-/home/xuancanhit/backups/hyper-authenticator/scheduled}
RETENTION_COUNT=${RETENTION_COUNT:-7}
MIN_FREE_KIB=${MIN_FREE_KIB:-10485760}
QUIESCE_STORAGE=${QUIESCE_STORAGE:-true}
DB_CONTAINER=${DB_CONTAINER:-supabase-db}
STORAGE_CONTAINER=${STORAGE_CONTAINER:-supabase-storage}

umask 077
mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"

exec 9>"$BACKUP_ROOT/.backup.lock"
if ! flock -n 9; then
  printf '%s\n' 'Một backup Supabase khác đang chạy.' >&2
  exit 75
fi

available_kib=$(df -Pk "$BACKUP_ROOT" | awk 'NR == 2 {print $4}')
if ((available_kib < MIN_FREE_KIB)); then
  printf 'Dung lượng trống không đủ: %s KiB, yêu cầu tối thiểu %s KiB.\n' \
    "$available_kib" "$MIN_FREE_KIB" >&2
  exit 1
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
final_dir="$BACKUP_ROOT/supabase-$timestamp"
work_dir=$(mktemp -d "$BACKUP_ROOT/.supabase-$timestamp.XXXXXX")
storage_stopped=false

cleanup() {
  local exit_code=$?
  if [[ "$storage_stopped" == true ]]; then
    docker start "$STORAGE_CONTAINER" >/dev/null || true
  fi
  if [[ $exit_code -ne 0 ]]; then
    rm -rf "$work_dir"
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

docker inspect "$DB_CONTAINER" >/dev/null
docker inspect "$STORAGE_CONTAINER" >/dev/null

if [[ "$QUIESCE_STORAGE" == true ]]; then
  docker stop --time 30 "$STORAGE_CONTAINER" >/dev/null
  storage_stopped=true
fi

docker exec "$DB_CONTAINER" pg_dump \
  -Fc -U supabase_admin -d postgres >"$work_dir/database-full.dump"
docker exec "$DB_CONTAINER" pg_dumpall \
  -U supabase_admin --globals-only >"$work_dir/database-globals.sql"

tar -C "$COMPOSE_DIR" -czf "$work_dir/storage-files.tar.gz" volumes/storage

config_paths=(.env volumes)
while IFS= read -r compose_path; do
  config_paths+=("${compose_path#"$COMPOSE_DIR/"}")
done < <(find "$COMPOSE_DIR" -maxdepth 1 -type f \
  \( -name 'compose*.yml' -o -name 'docker-compose*.yml' \) | sort)
tar -C "$COMPOSE_DIR" \
  --exclude='volumes/db/data' \
  --exclude='volumes/storage' \
  -czf "$work_dir/stack-config-sensitive.tar.gz" "${config_paths[@]}"

if [[ "$storage_stopped" == true ]]; then
  docker start "$STORAGE_CONTAINER" >/dev/null
  storage_stopped=false
fi

for _ in {1..60}; do
  storage_health=$(docker inspect --format '{{.State.Health.Status}}' \
    "$STORAGE_CONTAINER" 2>/dev/null || true)
  [[ "$storage_health" == healthy ]] && break
  sleep 1
done
[[ "${storage_health:-}" == healthy ]]

docker exec -i "$DB_CONTAINER" pg_restore --list \
  <"$work_dir/database-full.dump" >/dev/null
tar -tzf "$work_dir/storage-files.tar.gz" >/dev/null
tar -tzf "$work_dir/stack-config-sensitive.tar.gz" >/dev/null

cat >"$work_dir/manifest.txt" <<EOF
created_at_utc=$timestamp
database_container=$DB_CONTAINER
storage_quiesced=$QUIESCE_STORAGE
storage_consistency=database logical snapshot plus quiesced storage filesystem
restore_policy=restore into an isolated version-matched stack first
EOF

(
  cd "$work_dir"
  sha256sum \
    database-full.dump \
    database-globals.sql \
    storage-files.tar.gz \
    stack-config-sensitive.tar.gz \
    manifest.txt >SHA256SUMS
  sha256sum -c SHA256SUMS >/dev/null
)

find "$work_dir" -type f -exec chmod 600 {} +
chmod 700 "$work_dir"
mv "$work_dir" "$final_dir"
trap - EXIT INT TERM

mapfile -t old_backups < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name 'supabase-*' -printf '%f\n' | sort -r | tail -n "+$((RETENTION_COUNT + 1))"
)
for backup_name in "${old_backups[@]}"; do
  rm -rf -- "$BACKUP_ROOT/$backup_name"
done

printf 'Supabase backup pass: %s\n' "$final_dir"
