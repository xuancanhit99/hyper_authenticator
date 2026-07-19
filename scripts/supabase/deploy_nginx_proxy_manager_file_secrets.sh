#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR=${1:-/opt/stacks/nginx-proxy-manager-app}
BACKUP_ROOT=${2:-/home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager}
BUNDLE=${3:-}
CRITICAL_MANIFEST=${4:-}
EXCEPTION_MANIFEST=${5:--}
CONFIRMATION=${6:-}
APP_SERVICE=${NPM_APP_SERVICE:-nginx-proxy-manager-app}
DB_SERVICE=${NPM_DB_SERVICE:-nginx-proxy-manager-db}
APP_CONTAINER=${NPM_APP_CONTAINER:-nginx-proxy-manager-app}
DB_CONTAINER=${NPM_DB_CONTAINER:-nginx-proxy-manager-db}
ROUTE_INSTALL_DIR=${NPM_ROUTE_INSTALL_DIR:-/usr/local/lib/hyper-authenticator}
ROUTE_SERVICE=${NPM_ROUTE_SERVICE:-hyper-auth-nginx-proxy-manager-routes.service}
ROUTE_TIMER=${NPM_ROUTE_TIMER:-hyper-auth-nginx-proxy-manager-routes.timer}
MAX_BUNDLE_AGE_SECONDS=${NPM_FILE_SECRET_MAX_AGE_SECONDS:-7200}

if [[ -z "$BUNDLE" || -z "$CRITICAL_MANIFEST" ||
  "$CONFIRMATION" != '--allow-production-nginx-proxy-manager-file-secrets' ]]; then
  printf '%s\n' \
    'Usage: deploy_nginx_proxy_manager_file_secrets.sh COMPOSE_DIR BACKUP_ROOT BUNDLE CRITICAL_MANIFEST EXCEPTION_MANIFEST|- --allow-production-nginx-proxy-manager-file-secrets' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM file-secret deploy chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
for command_name in chown cmp cut date docker find flock grep install mktemp mv \
  realpath seq sha256sum sleep stat systemctl; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Thiếu NPM file-secret deploy dependency: %s\n' "$command_name" >&2
    exit 69
  }
done
if [[ ! "$MAX_BUNDLE_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'NPM_FILE_SECRET_MAX_AGE_SECONDS phải là số nguyên dương.' >&2
  exit 64
fi
if [[ ! -d "$COMPOSE_DIR" || ! -d "$BACKUP_ROOT" || ! -d "$BUNDLE" ||
  ! -f "$CRITICAL_MANIFEST" ]]; then
  printf '%s\n' 'NPM file-secret deploy input không đầy đủ.' >&2
  exit 66
fi

COMPOSE_DIR=$(realpath "$COMPOSE_DIR")
BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
BUNDLE=$(realpath "$BUNDLE")
CRITICAL_MANIFEST=$(realpath "$CRITICAL_MANIFEST")
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  EXCEPTION_MANIFEST=$(realpath "$EXCEPTION_MANIFEST")
fi
case "$BUNDLE/" in
  "$BACKUP_ROOT"/*) ;;
  *)
    printf '%s\n' 'NPM file-secret bundle phải nằm trong backup root.' >&2
    exit 64
    ;;
esac
for directory in "$BUNDLE" "$BUNDLE/secrets"; do
  mode=$(stat -c '%a' "$directory")
  if ((8#$mode & 8#077)); then
    printf 'NPM file-secret bundle directory không private: %s (%s).\n' \
      "$directory" "$mode" >&2
    exit 78
  fi
done

required_bundle_files=(
  METADATA.env SHA256SUMS compose.original.yaml env.original
  compose.candidate.yaml env.candidate secrets/npm_db_password
  secrets/npm_db_root_password route-harness/test_nginx_proxy_manager_route_matrix.sh
  route-harness/nginx_proxy_manager_database.sh
  route-harness/npm_database_exec_container.sh
)
for path in "${required_bundle_files[@]}"; do
  if [[ ! -f "$BUNDLE/$path" ]]; then
    printf 'NPM file-secret bundle thiếu file: %s\n' "$path" >&2
    exit 66
  fi
  mode=$(stat -c '%a' "$BUNDLE/$path")
  if ((8#$mode & 8#077)); then
    printf 'NPM file-secret bundle file không private: %s (%s).\n' \
      "$path" "$mode" >&2
    exit 78
  fi
done
for path in secrets/npm_db_password secrets/npm_db_root_password; do
  [[ $(stat -c '%a' "$BUNDLE/$path") == 400 ]] || {
    printf 'NPM bundle secret phải mode 0400: %s.\n' "$path" >&2
    exit 78
  }
done
(cd "$BUNDLE" && sha256sum --check SHA256SUMS)
grep -Fxq 'BUNDLE_FORMAT=hyper-auth-nginx-proxy-manager-file-secrets-v1' \
  "$BUNDLE/METADATA.env"
read_metadata() {
  grep -m1 "^${1}=" "$BUNDLE/METADATA.env" | cut -d= -f2-
}
backup_basename=$(read_metadata BACKUP_BASENAME)
created_at=$(read_metadata CREATED_AT)
app_image_id=$(read_metadata APP_IMAGE_ID)
app_version=$(read_metadata APP_VERSION)
db_image_id=$(read_metadata DB_IMAGE_ID)
critical_sha=$(read_metadata CRITICAL_MANIFEST_SHA256)
exception_sha=$(read_metadata EXCEPTION_MANIFEST_SHA256)
if [[ ! "$backup_basename" =~ ^npm-[0-9]{8}T[0-9]{6}Z$ ||
  ! "$created_at" =~ ^[0-9]{8}T[0-9]{6}Z$ ||
  ! "$app_image_id" =~ ^sha256:[0-9a-f]{64}$ ||
  ! "$db_image_id" =~ ^sha256:[0-9a-f]{64}$ ||
  ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'NPM file-secret metadata không hợp lệ.' >&2
  exit 64
fi
created_epoch=$(date -u -d \
  "${created_at:0:4}-${created_at:4:2}-${created_at:6:2}T${created_at:9:2}:${created_at:11:2}:${created_at:13:2}Z" \
  +%s 2>/dev/null || true)
now_epoch=$(date -u +%s)
if [[ ! "$created_epoch" =~ ^[0-9]+$ ]] || ((created_epoch > now_epoch)) ||
  ((now_epoch - created_epoch > MAX_BUNDLE_AGE_SECONDS)); then
  printf 'NPM file-secret bundle đã stale hoặc có timestamp không hợp lệ; giới hạn %s giây. Chạy lại preparation.\n' \
    "$MAX_BUNDLE_AGE_SECONDS" >&2
  exit 1
fi
BACKUP_DIR="$BACKUP_ROOT/$backup_basename"
for path in METADATA.env SHA256SUMS database-npm.sql config-app-letsencrypt.tar.gz; do
  [[ -f "$BACKUP_DIR/$path" ]] || {
    printf 'NPM rollback backup thiếu file: %s\n' "$path" >&2
    exit 66
  }
done
(cd "$BACKUP_DIR" && sha256sum --check SHA256SUMS)
[[ $(sha256sum "$CRITICAL_MANIFEST" | cut -d' ' -f1) == "$critical_sha" ]] || {
  printf '%s\n' 'NPM critical-route manifest đã drift.' >&2
  exit 1
}
if [[ "$EXCEPTION_MANIFEST" == '-' ]]; then
  [[ "$exception_sha" == none ]] || {
    printf '%s\n' 'NPM exception-manifest contract không khớp bundle.' >&2
    exit 1
  }
else
  [[ $(sha256sum "$EXCEPTION_MANIFEST" | cut -d' ' -f1) == "$exception_sha" ]] || {
    printf '%s\n' 'NPM route-exception manifest đã drift.' >&2
    exit 1
  }
fi

exec 9>"$BACKUP_ROOT/.file-secret-deploy.lock"
flock -n 9 || {
  printf '%s\n' 'Một NPM file-secret deploy khác đang chạy.' >&2
  exit 75
}
cd "$COMPOSE_DIR"
for path in compose.yaml .env; do
  mode=$(stat -c '%a' "$path")
  if ((8#$mode & 8#077)); then
    printf 'NPM production config không private: %s (%s).\n' "$path" "$mode" >&2
    exit 78
  fi
done
if ! cmp -s compose.yaml "$BUNDLE/compose.original.yaml" ||
  ! cmp -s .env "$BUNDLE/env.original"; then
  printf '%s\n' 'NPM production Compose/env đã drift khỏi bundle.' >&2
  exit 1
fi
if [[ -e "$COMPOSE_DIR/secrets" ]]; then
  printf '%s\n' 'NPM production secrets target đã tồn tại; từ chối ghi đè.' >&2
  exit 1
fi
docker compose config --quiet
docker compose --project-directory "$BUNDLE" \
  -f "$BUNDLE/compose.candidate.yaml" --env-file "$BUNDLE/env.candidate" \
  config --quiet
for container in "$APP_CONTAINER" "$DB_CONTAINER"; do
  [[ $(docker inspect "$container" --format '{{.State.Running}}') == true ]] || {
    printf 'NPM container không chạy trước deploy: %s\n' "$container" >&2
    exit 1
  }
done
if [[ $(docker inspect "$APP_CONTAINER" --format '{{.Image}}') != "$app_image_id" ||
  $(docker inspect "$DB_CONTAINER" --format '{{.Image}}') != "$db_image_id" ||
  $(docker exec "$APP_CONTAINER" node -p \
    'require("/app/package.json").version') != "$app_version" ]]; then
  printf '%s\n' 'NPM runtime đã drift khỏi prepared image/version.' >&2
  exit 1
fi

PRE_ROUTE="$BUNDLE/route-harness/test_nginx_proxy_manager_route_matrix.sh"
bash "$PRE_ROUTE" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
  --allow-production-nginx-proxy-manager-route-probe

compose_uid=$(stat -c '%u' compose.yaml)
compose_gid=$(stat -c '%g' compose.yaml)
rollback_route=$(mktemp -d "$BACKUP_ROOT/.file-secret-route-rollback.XXXXXX")
chmod 0700 "$rollback_route"
cleanup_tmp() {
  find "$COMPOSE_DIR/.compose.file-secrets.$$" "$COMPOSE_DIR/.env.file-secrets.$$" \
    -maxdepth 0 -type f -delete 2>/dev/null || true
  if [[ -d "$COMPOSE_DIR/.secrets.file-secrets.$$" ]]; then
    find "$COMPOSE_DIR/.secrets.file-secrets.$$" -depth -delete
  fi
}
trap cleanup_tmp EXIT

# Snapshot route harness before any production mutation. Failures above the
# transaction only leave private staging files and do not alter active config.
for name in test_nginx_proxy_manager_route_matrix.sh \
  nginx_proxy_manager_database.sh npm_database_exec_container.sh; do
  if [[ -e "$ROUTE_INSTALL_DIR/$name" ]]; then
    install -m 0600 "$ROUTE_INSTALL_DIR/$name" "$rollback_route/$name"
  else
    : >"$rollback_route/$name.absent"
  fi
done
install -d -m 0700 "$COMPOSE_DIR/.secrets.file-secrets.$$"
install -m 0400 "$BUNDLE/secrets/npm_db_password" \
  "$COMPOSE_DIR/.secrets.file-secrets.$$/npm_db_password"
install -m 0400 "$BUNDLE/secrets/npm_db_root_password" \
  "$COMPOSE_DIR/.secrets.file-secrets.$$/npm_db_root_password"
chown -R "$compose_uid:$compose_gid" "$COMPOSE_DIR/.secrets.file-secrets.$$"
install -m 0600 "$BUNDLE/compose.candidate.yaml" \
  "$COMPOSE_DIR/.compose.file-secrets.$$"
install -m 0600 "$BUNDLE/env.candidate" "$COMPOSE_DIR/.env.file-secrets.$$"
chown "$compose_uid:$compose_gid" "$COMPOSE_DIR/.compose.file-secrets.$$" \
  "$COMPOSE_DIR/.env.file-secrets.$$"

# shellcheck source=nginx_proxy_manager_database.sh
source "$BUNDLE/route-harness/nginx_proxy_manager_database.sh"
wait_database() {
  local attempt
  for attempt in $(seq 1 90); do
    if [[ $(docker inspect "$DB_CONTAINER" --format '{{.State.Running}}' \
      2>/dev/null || true) == true ]] &&
      npm_database_exec "$DB_CONTAINER" sh -lc \
        'mariadb --user="$MYSQL_USER" --database="$MYSQL_DATABASE" --batch --skip-column-names -e "SELECT 1"' \
        >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}
wait_app() {
  local attempt
  for attempt in $(seq 1 120); do
    if [[ $(docker inspect "$APP_CONTAINER" --format '{{.State.Running}}' \
      2>/dev/null || true) == true ]] &&
      docker exec "$APP_CONTAINER" node -e '
        require("http").get("http://127.0.0.1:81/api/", response => {
          response.resume(); process.exit(response.statusCode === 200 ? 0 : 1);
        }).on("error", () => process.exit(1));
      ' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}
runtime_gate() {
  wait_database
  wait_app
  [[ $(docker inspect "$APP_CONTAINER" --format '{{.Image}}') == "$app_image_id" ]]
  [[ $(docker inspect "$DB_CONTAINER" --format '{{.Image}}') == "$db_image_id" ]]
  [[ $(docker exec "$APP_CONTAINER" node -p \
    'require("/app/package.json").version') == "$app_version" ]]
  docker exec "$APP_CONTAINER" nginx -t >/dev/null
  table_count=$(npm_database_exec "$DB_CONTAINER" sh -lc '
    mariadb --user="$MYSQL_USER" --database="$MYSQL_DATABASE" \
      --batch --skip-column-names -e \
      "SELECT COUNT(*) FROM information_schema.tables
       WHERE table_schema = DATABASE()
         AND table_name IN (\"user\",\"proxy_host\",\"certificate\",\"setting\");"
  ')
  [[ "$table_count" == 4 ]]
  bash "$BUNDLE/route-harness/test_nginx_proxy_manager_route_matrix.sh" \
    "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
    --allow-production-nginx-proxy-manager-route-probe
}
file_secret_gate() {
  for container in "$APP_CONTAINER" "$DB_CONTAINER"; do
    ! docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' |
      grep -Eq '^(MYSQL|MARIADB|DB_MYSQL)_[A-Z_]*PASSWORD='
  done
  for contract in \
    "$APP_CONTAINER:/run/secrets/npm_db_password" \
    "$DB_CONTAINER:/run/secrets/npm_db_password" \
    "$DB_CONTAINER:/run/secrets/npm_db_root_password"; do
    container=${contract%%:*}
    destination=${contract#*:}
    docker inspect "$container" \
      --format '{{range .Mounts}}{{println .Destination}}{{end}}' |
      grep -Fxq "$destination"
  done
}

set +e
(
  set -e
  install -d -m 0755 "$ROUTE_INSTALL_DIR"
  for name in test_nginx_proxy_manager_route_matrix.sh \
    nginx_proxy_manager_database.sh npm_database_exec_container.sh; do
    install -m 0755 "$BUNDLE/route-harness/$name" "$ROUTE_INSTALL_DIR/$name"
  done
  mv "$COMPOSE_DIR/.secrets.file-secrets.$$" "$COMPOSE_DIR/secrets"
  mv "$COMPOSE_DIR/.env.file-secrets.$$" .env
  mv "$COMPOSE_DIR/.compose.file-secrets.$$" compose.yaml
  docker compose config --quiet
  docker compose up -d --no-deps --force-recreate "$DB_SERVICE"
  wait_database
  docker compose up -d --no-deps --force-recreate "$APP_SERVICE"
  runtime_gate
  file_secret_gate
  systemctl start "$ROUTE_SERVICE"
  [[ $(systemctl show "$ROUTE_SERVICE" -p Result --value) == success ]]
  systemctl is-active --quiet "$ROUTE_TIMER"
)
deploy_status=$?
set -e

if ((deploy_status != 0)); then
  printf '%s\n' 'NPM file-secret gate fail; bắt đầu automatic rollback.' >&2
  rollback_status=0
  install -m 0600 "$BUNDLE/env.original" \
    "$COMPOSE_DIR/.env.file-secrets.$$" || rollback_status=$?
  install -m 0600 "$BUNDLE/compose.original.yaml" \
    "$COMPOSE_DIR/.compose.file-secrets.$$" || rollback_status=$?
  if ((rollback_status == 0)); then
    chown "$compose_uid:$compose_gid" "$COMPOSE_DIR/.env.file-secrets.$$" \
      "$COMPOSE_DIR/.compose.file-secrets.$$" || rollback_status=$?
  fi
  if ((rollback_status == 0)); then
    mv "$COMPOSE_DIR/.env.file-secrets.$$" .env || rollback_status=$?
    mv "$COMPOSE_DIR/.compose.file-secrets.$$" compose.yaml || rollback_status=$?
  fi
  if ((rollback_status == 0)); then
    set +e
    (
      set -e
      docker compose config --quiet
      docker compose up -d --no-deps --force-recreate "$DB_SERVICE"
      wait_database
      docker compose up -d --no-deps --force-recreate "$APP_SERVICE"
      runtime_gate
    )
    rollback_status=$?
    set -e
  fi
  if ((rollback_status == 0)); then
    for name in test_nginx_proxy_manager_route_matrix.sh \
      nginx_proxy_manager_database.sh npm_database_exec_container.sh; do
      if [[ -f "$rollback_route/$name" ]]; then
        install -m 0755 "$rollback_route/$name" "$ROUTE_INSTALL_DIR/$name" || rollback_status=$?
      elif [[ -f "$rollback_route/$name.absent" ]]; then
        find "$ROUTE_INSTALL_DIR/$name" -maxdepth 0 -type f -delete || rollback_status=$?
      fi
    done
  fi
  if ((rollback_status == 0)); then
    systemctl start "$ROUTE_SERVICE" || rollback_status=$?
    [[ $(systemctl show "$ROUTE_SERVICE" -p Result --value) == success ]] || rollback_status=$?
    systemctl is-active --quiet "$ROUTE_TIMER" || rollback_status=$?
  fi
  if ((rollback_status == 0)) && [[ -d "$COMPOSE_DIR/secrets" ]]; then
    find "$COMPOSE_DIR/secrets" -depth -delete || rollback_status=$?
  fi
  if ((rollback_status != 0)); then
    printf 'CRITICAL: NPM automatic rollback không vượt runtime/route gate; giữ route snapshot tại %s.\n' \
      "$rollback_route" >&2
    exit 70
  fi
  find "$rollback_route" -depth -delete
  printf '%s\n' 'NPM rollback pass: exact Compose/env/runtime và route baseline đã khôi phục.' >&2
  exit "$deploy_status"
fi

find "$rollback_route" -depth -delete
trap - EXIT
cleanup_tmp
printf '%s\n' \
  'NPM production file-secret deploy pass: DB/app/API/Nginx/DB 4/4/routes/systemd.'
printf '%s\n' \
  'Plaintext password env đã biến mất; secret mounts và private host files đã xác minh.'
