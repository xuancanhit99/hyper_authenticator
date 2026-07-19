#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:-}
CONFIRMATION=${2:-}

if [[ -z "$BACKUP_DIR" ||
  "$CONFIRMATION" != '--allow-isolated-nginx-proxy-manager-restore' ]]; then
  printf '%s\n' \
    'Usage: rehearse_nginx_proxy_manager_backup.sh BACKUP_DIR --allow-isolated-nginx-proxy-manager-restore' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM restore rehearsal chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
for command_name in cmp cut date docker find grep mktemp openssl realpath seq \
  sha256sum sleep stat tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu NPM restore dependency: %s\n' "$command_name" >&2
    exit 69
  fi
done

BACKUP_DIR=$(realpath "$BACKUP_DIR")
for name in METADATA.env SHA256SUMS archive.list \
  config-app-letsencrypt.tar.gz database-npm.sql; do
  if [[ ! -f "$BACKUP_DIR/$name" ]]; then
    printf 'NPM backup thiếu file: %s\n' "$name" >&2
    exit 66
  fi
  mode=$(stat -c '%a' "$BACKUP_DIR/$name")
  if ((8#$mode & 8#077)); then
    printf 'NPM backup file không private: %s (%s).\n' "$name" "$mode" >&2
    exit 78
  fi
done

(cd "$BACKUP_DIR" && sha256sum --check SHA256SUMS)
grep -Fxq 'BACKUP_FORMAT=hyper-auth-nginx-proxy-manager-v1' \
  "$BACKUP_DIR/METADATA.env"
read_metadata() {
  local key=$1
  grep -m1 "^${key}=" "$BACKUP_DIR/METADATA.env" | cut -d= -f2-
}
db_image_id=$(read_metadata DB_IMAGE_ID)
if [[ ! "$db_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  printf '%s\n' 'NPM backup metadata thiếu DB image ID hợp lệ.' >&2
  exit 1
fi
db_name=$(read_metadata DB_NAME)
if [[ ! "$db_name" =~ ^[A-Za-z0-9_]+$ ]]; then
  printf '%s\n' 'NPM backup metadata thiếu database name hợp lệ.' >&2
  exit 1
fi
docker image inspect "$db_image_id" >/dev/null

listing_tmp=$(mktemp "${TMPDIR:-/tmp}/hyper-auth-npm-listing.XXXXXX")
chmod 0600 "$listing_tmp"
cleanup_listing() {
  find "$listing_tmp" -maxdepth 0 -type f -delete 2>/dev/null || true
}
trap cleanup_listing EXIT
tar -tzf "$BACKUP_DIR/config-app-letsencrypt.tar.gz" >"$listing_tmp"
if ! cmp -s "$BACKUP_DIR/archive.list" "$listing_tmp"; then
  printf '%s\n' 'NPM archive listing không khớp backup evidence.' >&2
  exit 1
fi
find "$listing_tmp" -maxdepth 0 -type f -delete
trap - EXIT

container="hyper-auth-npm-restore-$(date -u +%Y%m%dT%H%M%SZ)-$$"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-npm-restore.XXXXXX")
chmod 0700 "$sandbox"
env_file="$sandbox/mariadb.env"
umask 077
printf 'MARIADB_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)" >"$env_file"
chmod 0600 "$env_file"
container_created=false
cleanup() {
  if [[ "$container_created" == true ]]; then
    docker stop --time 10 "$container" >/dev/null 2>&1 || true
    docker container rm "$container" >/dev/null 2>&1 || true
  fi
  find "$sandbox" -depth -delete
}
trap cleanup EXIT

docker run --detach \
  --name "$container" \
  --network none \
  --env-file "$env_file" \
  "$db_image_id" >/dev/null
container_created=true

ready=false
for _ in $(seq 1 60); do
  if docker exec "$container" sh -lc \
    'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb --user=root \
      --batch --skip-column-names -e "SELECT 1"' \
    >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  printf '%s\n' 'MariaDB rehearsal không ready trong 60 giây.' >&2
  exit 1
fi

docker exec --interactive "$container" sh -lc \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb --user=root' \
  <"$BACKUP_DIR/database-npm.sql"

table_count=$(docker exec "$container" sh -lc '
  MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb --user=root \
    --database="$1" --batch --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema = DATABASE()
       AND table_name IN (\"user\", \"proxy_host\", \"certificate\", \"setting\");"
' sh "$db_name")
if [[ "$table_count" != 4 ]]; then
  printf 'NPM restore thiếu core table: %s/4.\n' "$table_count" >&2
  exit 1
fi

docker stop --time 10 "$container" >/dev/null
docker container rm "$container" >/dev/null
container_created=false
find "$sandbox" -depth -delete
trap - EXIT

printf '%s\n' \
  'NPM restore rehearsal pass: checksum/archive và bốn core table trong isolated MariaDB.'
