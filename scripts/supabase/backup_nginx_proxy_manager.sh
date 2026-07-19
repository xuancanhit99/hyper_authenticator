#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR=${1:-/opt/stacks/nginx-proxy-manager-app}
BACKUP_ROOT=${2:-/home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager}
CONFIRMATION=${3:-}
RETENTION_COUNT=${NPM_BACKUP_RETENTION_COUNT:-7}
APP_CONTAINER=${NPM_APP_CONTAINER:-nginx-proxy-manager-app}
DB_CONTAINER=${NPM_DB_CONTAINER:-nginx-proxy-manager-db}

if [[ "$CONFIRMATION" != '--allow-nginx-proxy-manager-backup' ]]; then
  printf '%s\n' \
    'Usage: backup_nginx_proxy_manager.sh COMPOSE_DIR BACKUP_ROOT --allow-nginx-proxy-manager-backup' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM production backup chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
if [[ ! "$RETENTION_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  printf 'NPM_BACKUP_RETENTION_COUNT phải là số nguyên dương: %s\n' \
    "$RETENTION_COUNT" >&2
  exit 64
fi
for command_name in awk chmod date df docker find flock grep install mv realpath \
  sha256sum sort stat tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu NPM backup dependency: %s\n' "$command_name" >&2
    exit 69
  fi
done
if [[ ! -d "$COMPOSE_DIR" || ! -f "$COMPOSE_DIR/compose.yaml" ||
  ! -f "$COMPOSE_DIR/.env" ]]; then
  printf 'NPM compose contract không đầy đủ: %s\n' "$COMPOSE_DIR" >&2
  exit 66
fi

umask 077
install -d -m 0700 "$BACKUP_ROOT"
compose_real=$(realpath "$COMPOSE_DIR")
backup_real=$(realpath "$BACKUP_ROOT")
case "$backup_real/" in
  "$compose_real/"*)
    printf '%s\n' 'NPM backup root không được nằm trong compose directory.' >&2
    exit 64
    ;;
esac
available_kib=$(df -Pk "$BACKUP_ROOT" | awk 'NR == 2 {print $4}')
if [[ ! "$available_kib" =~ ^[0-9]+$ ]] || ((available_kib < 1048576)); then
  printf 'NPM backup cần ít nhất 1 GiB trống, hiện có %s KiB.\n' \
    "${available_kib:-unknown}" >&2
  exit 1
fi
exec 9>"$BACKUP_ROOT/.backup.lock"
if ! flock -n 9; then
  printf '%s\n' 'Một NPM backup khác đang chạy.' >&2
  exit 75
fi

cd "$COMPOSE_DIR"
docker compose config --quiet
for sensitive_path in compose.yaml .env data/app/keys.json; do
  if [[ ! -f "$sensitive_path" ]]; then
    printf 'Thiếu NPM sensitive file: %s\n' "$sensitive_path" >&2
    exit 66
  fi
  mode=$(stat -c '%a' "$sensitive_path")
  if ((8#$mode & 8#077)); then
    printf 'NPM sensitive file phải mode 0600 hoặc chặt hơn: %s (%s).\n' \
      "$sensitive_path" "$mode" >&2
    exit 78
  fi
done
for container in "$APP_CONTAINER" "$DB_CONTAINER"; do
  if [[ $(docker inspect "$container" --format '{{.State.Running}}') != true ]]; then
    printf 'NPM container không chạy: %s\n' "$container" >&2
    exit 1
  fi
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
final_dir="$BACKUP_ROOT/npm-$stamp"
work_dir="$BACKUP_ROOT/.npm-$stamp.tmp.$$"
if [[ -e "$final_dir" || -e "$work_dir" ]]; then
  printf '%s\n' 'NPM backup destination đã tồn tại.' >&2
  exit 1
fi
install -d -m 0700 "$work_dir"
cleanup() {
  if [[ -d "$work_dir" ]]; then
    find "$work_dir" -depth -delete
  fi
}
trap cleanup EXIT

docker exec "$DB_CONTAINER" sh -lc '
  MYSQL_PWD="$MYSQL_PASSWORD" exec mariadb-dump \
    --user="$MYSQL_USER" \
    --databases "$MYSQL_DATABASE" \
    --single-transaction \
    --no-tablespaces \
    --routines \
    --events \
    --triggers
' >"$work_dir/database-npm.sql"

tar -C "$COMPOSE_DIR" \
  --exclude='data/mysql' \
  --exclude='data/app/logs' \
  -czf "$work_dir/config-app-letsencrypt.tar.gz" \
  compose.yaml .env data/app data/letsencrypt

app_image=$(docker inspect "$APP_CONTAINER" --format '{{.Image}}')
db_image=$(docker inspect "$DB_CONTAINER" --format '{{.Image}}')
db_name=$(docker exec "$DB_CONTAINER" sh -lc 'printf "%s" "$MYSQL_DATABASE"')
if [[ ! "$db_name" =~ ^[A-Za-z0-9_]+$ ]]; then
  printf '%s\n' 'NPM database name không hợp lệ cho restore metadata.' >&2
  exit 1
fi
cat >"$work_dir/METADATA.env" <<EOF
BACKUP_FORMAT=hyper-auth-nginx-proxy-manager-v1
CREATED_AT=$stamp
APP_CONTAINER=$APP_CONTAINER
APP_IMAGE_ID=$app_image
DB_CONTAINER=$DB_CONTAINER
DB_IMAGE_ID=$db_image
DB_NAME=$db_name
EOF

if [[ ! -s "$work_dir/database-npm.sql" ]] ||
  ! grep -Fq 'CREATE DATABASE' "$work_dir/database-npm.sql"; then
  printf '%s\n' 'NPM database dump không đạt validation.' >&2
  exit 1
fi
archive_listing="$work_dir/archive.list"
tar -tzf "$work_dir/config-app-letsencrypt.tar.gz" >"$archive_listing"
for expected_path in \
  compose.yaml \
  .env \
  data/app/keys.json \
  data/letsencrypt/; do
  if ! grep -Fxq "$expected_path" "$archive_listing"; then
    printf 'NPM backup archive thiếu path: %s\n' "$expected_path" >&2
    exit 1
  fi
done
find "$work_dir" -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' |
  LC_ALL=C sort |
  while IFS= read -r name; do
    (cd "$work_dir" && sha256sum "$name")
  done >"$work_dir/SHA256SUMS"
(cd "$work_dir" && sha256sum --check SHA256SUMS)

find "$work_dir" -type d -exec chmod 0700 {} +
find "$work_dir" -type f -exec chmod 0600 {} +
mv "$work_dir" "$final_dir"
trap - EXIT
if ! (cd "$final_dir" && sha256sum --check SHA256SUMS); then
  invalid_dir="$BACKUP_ROOT/.invalid-$(basename "$final_dir")-checksum"
  mv "$final_dir" "$invalid_dir"
  printf 'NPM backup post-move checksum fail; giữ tại %s.\n' \
    "$invalid_dir" >&2
  exit 1
fi

mapfile -t backups < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name 'npm-[0-9]*T[0-9]*Z' -printf '%f\n' | LC_ALL=C sort
)
if ((${#backups[@]} > RETENTION_COUNT)); then
  delete_count=$((${#backups[@]} - RETENTION_COUNT))
  for ((index = 0; index < delete_count; index++)); do
    find "$BACKUP_ROOT/${backups[$index]}" -depth -delete
  done
fi

printf 'NPM production backup pass: %s\n' "$final_dir"
printf '%s\n' \
  'Transactional DB dump, config/app/Let’s Encrypt archive và checksum đều hợp lệ.'
