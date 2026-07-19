#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:-}
TARGET_IMAGE_ID=${2:-}
TARGET_VERSION=${3:-}
CONFIRMATION=${4:-}

if [[ -z "$BACKUP_DIR" || -z "$TARGET_IMAGE_ID" || -z "$TARGET_VERSION" ||
  "$CONFIRMATION" != '--allow-isolated-nginx-proxy-manager-upgrade' ]]; then
  printf '%s\n' \
    'Usage: rehearse_nginx_proxy_manager_upgrade.sh BACKUP_DIR TARGET_IMAGE_ID TARGET_VERSION --allow-isolated-nginx-proxy-manager-upgrade' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM upgrade rehearsal chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
if [[ ! "$TARGET_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]] ||
  [[ ! "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'Target NPM phải có exact image ID và semantic version.' >&2
  exit 64
fi
for command_name in cmp cut date docker find grep mktemp openssl realpath seq \
  sha256sum sleep stat tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu NPM upgrade dependency: %s\n' "$command_name" >&2
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
db_name=$(read_metadata DB_NAME)
if [[ ! "$db_image_id" =~ ^sha256:[0-9a-f]{64}$ ]] ||
  [[ ! "$db_name" =~ ^[A-Za-z0-9_]+$ ]]; then
  printf '%s\n' 'NPM backup metadata thiếu DB image/name hợp lệ.' >&2
  exit 1
fi
docker image inspect "$db_image_id" "$TARGET_IMAGE_ID" >/dev/null
actual_target_id=$(docker image inspect "$TARGET_IMAGE_ID" --format '{{.Id}}')
if [[ "$actual_target_id" != "$TARGET_IMAGE_ID" ]]; then
  printf '%s\n' 'NPM target image ID không khớp local image.' >&2
  exit 1
fi

listing_tmp=$(mktemp "${TMPDIR:-/tmp}/hyper-auth-npm-upgrade-listing.XXXXXX")
chmod 0600 "$listing_tmp"
trap 'find "$listing_tmp" -maxdepth 0 -type f -delete 2>/dev/null || true' EXIT
tar -tzf "$BACKUP_DIR/config-app-letsencrypt.tar.gz" >"$listing_tmp"
if ! cmp -s "$BACKUP_DIR/archive.list" "$listing_tmp"; then
  printf '%s\n' 'NPM archive listing không khớp backup evidence.' >&2
  exit 1
fi
find "$listing_tmp" -maxdepth 0 -type f -delete
trap - EXIT

suffix="$(date -u +%Y%m%dT%H%M%SZ)-$$"
network="hyper-auth-npm-canary-$suffix"
db_container="hyper-auth-npm-canary-db-$suffix"
app_container="hyper-auth-npm-canary-app-$suffix"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-npm-canary.XXXXXX")
chmod 0700 "$sandbox"
network_created=false
db_created=false
app_created=false
cleanup() {
  if [[ "$app_created" == true ]]; then
    docker container rm --force --volumes "$app_container" >/dev/null 2>&1 || true
  fi
  if [[ "$db_created" == true ]]; then
    docker container rm --force --volumes "$db_container" >/dev/null 2>&1 || true
  fi
  if [[ "$network_created" == true ]]; then
    docker network rm "$network" >/dev/null 2>&1 || true
  fi
  find "$sandbox" -depth -delete
}
trap cleanup EXIT

tar -xzf "$BACKUP_DIR/config-app-letsencrypt.tar.gz" -C "$sandbox" \
  data/app data/letsencrypt
mkdir -p "$sandbox/data/app/logs"
chmod 0700 "$sandbox/data/app/logs"
umask 077
secrets_dir="$sandbox/secrets"
mkdir -m 0700 "$secrets_dir"
root_secret="$secrets_dir/npm_db_root_password"
app_secret="$secrets_dir/npm_db_password"
openssl rand -hex 24 >"$root_secret"
openssl rand -hex 24 >"$app_secret"
chmod 0400 "$root_secret" "$app_secret"
db_env="$sandbox/mariadb.env"
app_env="$sandbox/npm.env"
cat >"$db_env" <<EOF
MARIADB_ROOT_PASSWORD_FILE=/run/secrets/npm_db_root_password
MARIADB_DATABASE=$db_name
MARIADB_USER=npm_canary
MARIADB_PASSWORD_FILE=/run/secrets/npm_db_password
EOF
cat >"$app_env" <<EOF
DB_MYSQL_HOST=$db_container
DB_MYSQL_PORT=3306
DB_MYSQL_USER=npm_canary
DB_MYSQL_PASSWORD__FILE=/run/secrets/npm_db_password
DB_MYSQL_NAME=$db_name
DISABLE_IPV6=true
EOF
chmod 0600 "$db_env" "$app_env"

docker network create --internal "$network" >/dev/null
network_created=true
docker run --detach \
  --name "$db_container" \
  --network "$network" \
  --env-file "$db_env" \
  --volume "$root_secret:/run/secrets/npm_db_root_password:ro" \
  --volume "$app_secret:/run/secrets/npm_db_password:ro" \
  "$db_image_id" >/dev/null
db_created=true

db_ready=false
for _ in $(seq 1 60); do
  if docker exec "$db_container" sh -lc \
    'MYSQL_PWD=$(cat -- "$MARIADB_ROOT_PASSWORD_FILE") mariadb --user=root \
      --batch --skip-column-names -e "SELECT 1"' \
    >/dev/null 2>&1; then
    db_ready=true
    break
  fi
  sleep 1
done
if [[ "$db_ready" != true ]]; then
  printf '%s\n' 'MariaDB canary không ready trong 60 giây.' >&2
  exit 1
fi
docker exec --interactive "$db_container" sh -lc \
  'MYSQL_PWD=$(cat -- "$MARIADB_ROOT_PASSWORD_FILE") mariadb --user=root' \
  <"$BACKUP_DIR/database-npm.sql"

docker run --detach \
  --name "$app_container" \
  --network "$network" \
  --env-file "$app_env" \
  --volume "$app_secret:/run/secrets/npm_db_password:ro" \
  --volume "$sandbox/data/app:/data" \
  --volume "$sandbox/data/letsencrypt:/etc/letsencrypt" \
  "$TARGET_IMAGE_ID" >/dev/null
app_created=true

app_ready=false
for _ in $(seq 1 120); do
  if [[ $(docker inspect "$app_container" --format '{{.State.Running}}') != true ]]; then
    printf '%s\n' 'NPM canary dừng trước khi ready.' >&2
    exit 1
  fi
  if docker exec "$app_container" node -e '
    require("http").get("http://127.0.0.1:81/api/", response => {
      response.resume();
      process.exit(response.statusCode === 200 ? 0 : 1);
    }).on("error", () => process.exit(1));
  ' >/dev/null 2>&1; then
    app_ready=true
    break
  fi
  sleep 1
done
if [[ "$app_ready" != true ]]; then
  printf '%s\n' 'NPM canary API không ready trong 120 giây.' >&2
  exit 1
fi

actual_version=$(docker exec "$app_container" node -p \
  'require("/app/package.json").version')
if [[ "$actual_version" != "$TARGET_VERSION" ]]; then
  printf 'NPM canary version mismatch: %s != %s.\n' \
    "$actual_version" "$TARGET_VERSION" >&2
  exit 1
fi
docker exec "$app_container" nginx -t >/dev/null
if [[ $(docker network inspect "$network" --format '{{.Internal}}') != true ]]; then
  printf '%s\n' 'NPM canary network không internal.' >&2
  exit 1
fi
port_bindings=$(docker inspect "$app_container" \
  --format '{{json .HostConfig.PortBindings}}')
if [[ "$port_bindings" != null && "$port_bindings" != '{}' ]]; then
  printf '%s\n' 'NPM canary không được publish host port.' >&2
  exit 1
fi
for container in "$db_container" "$app_container"; do
  if docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' |
    grep -Eq '^(MYSQL|MARIADB|DB_MYSQL)_[A-Z_]*PASSWORD='; then
    printf 'NPM canary còn plaintext password env: %s.\n' "$container" >&2
    exit 1
  fi
done
for mount_contract in \
  "$db_container:/run/secrets/npm_db_root_password" \
  "$db_container:/run/secrets/npm_db_password" \
  "$app_container:/run/secrets/npm_db_password"; do
  container=${mount_contract%%:*}
  destination=${mount_contract#*:}
  if ! docker inspect "$container" \
    --format '{{range .Mounts}}{{println .Destination}}{{end}}' |
    grep -Fxq "$destination"; then
    printf 'NPM canary thiếu secret mount: %s.\n' "$destination" >&2
    exit 1
  fi
done
table_count=$(docker exec "$db_container" sh -lc '
  MYSQL_PWD=$(cat -- "$MARIADB_ROOT_PASSWORD_FILE") mariadb --user=root \
    --database="$1" --batch --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema = DATABASE()
       AND table_name IN (\"user\", \"proxy_host\", \"certificate\", \"setting\");"
' sh "$db_name")
if [[ "$table_count" != 4 ]]; then
  printf 'NPM canary thiếu core table sau migration: %s/4.\n' "$table_count" >&2
  exit 1
fi

docker container rm --force --volumes "$app_container" >/dev/null
app_created=false
docker container rm --force --volumes "$db_container" >/dev/null
db_created=false
docker network rm "$network" >/dev/null
network_created=false
find "$sandbox" -depth -delete
trap - EXIT

printf 'NPM isolated upgrade rehearsal pass: version %s, API/Nginx/DB 4/4.\n' \
  "$actual_version"
printf '%s\n' \
  'Docker file secrets, internal network, no host port; canary container/volume/sandbox đã cleanup.'
