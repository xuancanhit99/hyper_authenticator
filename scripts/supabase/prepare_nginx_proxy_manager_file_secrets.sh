#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR=${1:-/opt/stacks/nginx-proxy-manager-app}
BACKUP_ROOT=${2:-/home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager}
CRITICAL_MANIFEST=${3:-}
EXCEPTION_MANIFEST=${4:--}
CONFIRMATION=${5:-}
APP_CONTAINER=${NPM_APP_CONTAINER:-nginx-proxy-manager-app}
DB_CONTAINER=${NPM_DB_CONTAINER:-nginx-proxy-manager-db}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROUTE_SCRIPT=${NPM_ROUTE_SCRIPT:-$SCRIPT_DIR/test_nginx_proxy_manager_route_matrix.sh}
BACKUP_SCRIPT=${NPM_BACKUP_SCRIPT:-$SCRIPT_DIR/backup_nginx_proxy_manager.sh}
RESTORE_SCRIPT=${NPM_RESTORE_SCRIPT:-$SCRIPT_DIR/rehearse_nginx_proxy_manager_backup.sh}
CANARY_SCRIPT=${NPM_CANARY_SCRIPT:-$SCRIPT_DIR/rehearse_nginx_proxy_manager_upgrade.sh}
RENDERER=${NPM_FILE_SECRET_RENDERER:-$SCRIPT_DIR/render_nginx_proxy_manager_file_secrets.py}

if [[ -z "$CRITICAL_MANIFEST" ||
  "$CONFIRMATION" != '--allow-nginx-proxy-manager-file-secret-preparation' ]]; then
  printf '%s\n' \
    'Usage: prepare_nginx_proxy_manager_file_secrets.sh COMPOSE_DIR BACKUP_ROOT CRITICAL_MANIFEST EXCEPTION_MANIFEST|- --allow-nginx-proxy-manager-file-secret-preparation' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM file-secret preparation chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
for command_name in awk basename date docker find flock grep install mktemp mv \
  python3 realpath sed sha256sum stat tail; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Thiếu NPM file-secret preparation dependency: %s\n' "$command_name" >&2
    exit 69
  }
done
for executable in "$ROUTE_SCRIPT" "$BACKUP_SCRIPT" "$RESTORE_SCRIPT" \
  "$CANARY_SCRIPT" "$RENDERER"; do
  [[ -x "$executable" ]] || {
    printf 'Thiếu executable NPM preparation dependency: %s\n' "$executable" >&2
    exit 66
  }
done
if [[ ! -d "$COMPOSE_DIR" || ! -f "$COMPOSE_DIR/compose.yaml" ||
  ! -f "$COMPOSE_DIR/.env" || ! -f "$CRITICAL_MANIFEST" ]]; then
  printf '%s\n' 'NPM file-secret preparation input không đầy đủ.' >&2
  exit 66
fi

COMPOSE_DIR=$(realpath "$COMPOSE_DIR")
install -d -m 0700 "$BACKUP_ROOT"
BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
CRITICAL_MANIFEST=$(realpath "$CRITICAL_MANIFEST")
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  EXCEPTION_MANIFEST=$(realpath "$EXCEPTION_MANIFEST")
fi
case "$BACKUP_ROOT/" in
  "$COMPOSE_DIR"/*)
    printf '%s\n' 'NPM backup root không được nằm trong Compose directory.' >&2
    exit 64
    ;;
esac
for path in "$COMPOSE_DIR/compose.yaml" "$COMPOSE_DIR/.env" \
  "$CRITICAL_MANIFEST"; do
  mode=$(stat -c '%a' "$path")
  if ((8#$mode & 8#077)); then
    printf 'NPM preparation input không private: %s (%s).\n' "$path" "$mode" >&2
    exit 78
  fi
done
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  mode=$(stat -c '%a' "$EXCEPTION_MANIFEST")
  if ((8#$mode & 8#077)); then
    printf '%s\n' 'NPM route exception manifest không private.' >&2
    exit 78
  fi
fi

umask 077
exec 9>"$BACKUP_ROOT/.file-secret-prepare.lock"
flock -n 9 || {
  printf '%s\n' 'Một NPM file-secret preparation khác đang chạy.' >&2
  exit 75
}

cd "$COMPOSE_DIR"
docker compose config --quiet
for container in "$APP_CONTAINER" "$DB_CONTAINER"; do
  if [[ $(docker inspect "$container" --format '{{.State.Running}}') != true ]]; then
    printf 'NPM container không chạy: %s\n' "$container" >&2
    exit 1
  fi
done
app_image_id=$(docker inspect "$APP_CONTAINER" --format '{{.Image}}')
db_image_id=$(docker inspect "$DB_CONTAINER" --format '{{.Image}}')
app_version=$(docker exec "$APP_CONTAINER" node -p \
  'require("/app/package.json").version')
if [[ ! "$app_image_id" =~ ^sha256:[0-9a-f]{64}$ ||
  ! "$db_image_id" =~ ^sha256:[0-9a-f]{64}$ ||
  ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'NPM runtime thiếu exact image ID/version.' >&2
  exit 1
fi

"$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
  --allow-production-nginx-proxy-manager-route-probe

backup_log=$(mktemp "${TMPDIR:-/tmp}/hyper-auth-npm-secret-backup.XXXXXX")
work_dir=''
cleanup() {
  find "$backup_log" -maxdepth 0 -type f -delete 2>/dev/null || true
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    find "$work_dir" -depth -delete
  fi
}
trap cleanup EXIT
"$BACKUP_SCRIPT" "$COMPOSE_DIR" "$BACKUP_ROOT" \
  --allow-nginx-proxy-manager-backup >"$backup_log"
backup_dir=$(sed -n 's/^NPM production backup pass: //p' "$backup_log" | tail -1)
if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
  printf '%s\n' 'Không xác định được fresh NPM rollback backup.' >&2
  exit 1
fi
backup_dir=$(realpath "$backup_dir")
grep -E '^(NPM production backup pass:|Transactional DB dump)' "$backup_log"
"$RESTORE_SCRIPT" "$backup_dir" --allow-isolated-nginx-proxy-manager-restore
"$CANARY_SCRIPT" "$backup_dir" "$app_image_id" "$app_version" \
  --allow-isolated-nginx-proxy-manager-upgrade
"$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
  --allow-production-nginx-proxy-manager-route-probe

stamp=$(date -u +%Y%m%dT%H%M%SZ)
final_dir="$BACKUP_ROOT/file-secrets-npm-$stamp"
work_dir="$BACKUP_ROOT/.file-secrets-npm-$stamp.tmp.$$"
if [[ -e "$final_dir" || -e "$work_dir" ]]; then
  printf '%s\n' 'NPM file-secret bundle destination đã tồn tại.' >&2
  exit 1
fi
install -d -m 0700 "$work_dir" "$work_dir/route-harness"
install -m 0600 "$COMPOSE_DIR/compose.yaml" "$work_dir/compose.original.yaml"
install -m 0600 "$COMPOSE_DIR/.env" "$work_dir/env.original"
resolved="$work_dir/compose.resolved.json"
docker compose config --format json >"$resolved"
chmod 0600 "$resolved"
"$RENDERER" "$resolved" "$COMPOSE_DIR/.env" \
  "$work_dir/compose.candidate.yaml" "$work_dir/env.candidate" \
  "$work_dir/secrets"
find "$resolved" -maxdepth 0 -type f -delete

docker compose --project-directory "$work_dir" \
  -f "$work_dir/compose.candidate.yaml" \
  --env-file "$work_dir/env.candidate" config --quiet
for name in test_nginx_proxy_manager_route_matrix.sh \
  nginx_proxy_manager_database.sh npm_database_exec_container.sh; do
  install -m 0600 "$SCRIPT_DIR/$name" "$work_dir/route-harness/$name"
done

cat >"$work_dir/METADATA.env" <<EOF
BUNDLE_FORMAT=hyper-auth-nginx-proxy-manager-file-secrets-v1
CREATED_AT=$stamp
BACKUP_BASENAME=$(basename "$backup_dir")
APP_IMAGE_ID=$app_image_id
APP_VERSION=$app_version
DB_IMAGE_ID=$db_image_id
COMPOSE_SHA256=$(sha256sum "$COMPOSE_DIR/compose.yaml" | awk '{print $1}')
ENV_SHA256=$(sha256sum "$COMPOSE_DIR/.env" | awk '{print $1}')
CRITICAL_MANIFEST_SHA256=$(sha256sum "$CRITICAL_MANIFEST" | awk '{print $1}')
EXCEPTION_MANIFEST_SHA256=$(
  if [[ "$EXCEPTION_MANIFEST" == '-' ]]; then printf 'none';
  else sha256sum "$EXCEPTION_MANIFEST" | awk '{print $1}'; fi
)
EOF
find "$work_dir" -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort |
  while IFS= read -r name; do
    (cd "$work_dir" && sha256sum "$name")
  done >"$work_dir/SHA256SUMS"
(cd "$work_dir" && sha256sum --check SHA256SUMS)
find "$work_dir" -type d -exec chmod 0700 {} +
find "$work_dir" -type f -exec chmod 0600 {} +
chmod 0400 "$work_dir/secrets/npm_db_password" \
  "$work_dir/secrets/npm_db_root_password"
mv "$work_dir" "$final_dir"
work_dir=''
(cd "$final_dir" && sha256sum --check SHA256SUMS)
trap - EXIT
find "$backup_log" -maxdepth 0 -type f -delete

printf 'NPM file-secret preparation pass: %s\n' "$final_dir"
printf 'Fresh rollback backup: %s\n' "$backup_dir"
printf '%s\n' \
  'Candidate/secret/checksum đã tạo private; production Compose/container chưa bị thay đổi.'
