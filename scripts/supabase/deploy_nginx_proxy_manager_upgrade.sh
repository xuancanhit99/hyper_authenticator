#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR=${1:-/opt/stacks/nginx-proxy-manager-app}
BACKUP_ROOT=${2:-/home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager}
MAINTENANCE_BUNDLE=${3:-}
CRITICAL_MANIFEST=${4:-}
EXCEPTION_MANIFEST=${5:--}
CONFIRMATION=${6:-}
APP_SERVICE=${NPM_APP_SERVICE:-nginx-proxy-manager-app}
APP_CONTAINER=${NPM_APP_CONTAINER:-nginx-proxy-manager-app}
DB_CONTAINER=${NPM_DB_CONTAINER:-nginx-proxy-manager-db}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROUTE_SCRIPT=${NPM_ROUTE_SCRIPT:-$SCRIPT_DIR/test_nginx_proxy_manager_route_matrix.sh}

if [[ -z "$MAINTENANCE_BUNDLE" || -z "$CRITICAL_MANIFEST" ||
  "$CONFIRMATION" != '--allow-production-nginx-proxy-manager-upgrade' ]]; then
  printf '%s\n' \
    'Usage: deploy_nginx_proxy_manager_upgrade.sh COMPOSE_DIR BACKUP_ROOT MAINTENANCE_BUNDLE CRITICAL_MANIFEST EXCEPTION_MANIFEST|- --allow-production-nginx-proxy-manager-upgrade' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM production upgrade chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
for command_name in awk basename chown cmp cut date docker find flock grep install mv \
  realpath seq sha256sum sleep stat; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu NPM deployment dependency: %s\n' "$command_name" >&2
    exit 69
  fi
done
if [[ ! -x "$ROUTE_SCRIPT" ]]; then
  printf 'Thiếu executable NPM route gate: %s\n' "$ROUTE_SCRIPT" >&2
  exit 66
fi
if [[ ! -d "$COMPOSE_DIR" || ! -f "$COMPOSE_DIR/compose.yaml" ||
  ! -f "$COMPOSE_DIR/.env" || ! -d "$BACKUP_ROOT" ||
  ! -d "$MAINTENANCE_BUNDLE" || ! -f "$CRITICAL_MANIFEST" ]]; then
  printf '%s\n' 'NPM production-upgrade input không đầy đủ.' >&2
  exit 66
fi

COMPOSE_DIR=$(realpath "$COMPOSE_DIR")
BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
MAINTENANCE_BUNDLE=$(realpath "$MAINTENANCE_BUNDLE")
CRITICAL_MANIFEST=$(realpath "$CRITICAL_MANIFEST")
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  EXCEPTION_MANIFEST=$(realpath "$EXCEPTION_MANIFEST")
fi
case "$MAINTENANCE_BUNDLE/" in
  "$BACKUP_ROOT"/*) ;;
  *)
    printf '%s\n' 'NPM maintenance bundle phải nằm trong backup root.' >&2
    exit 64
    ;;
esac

for path in METADATA.env SHA256SUMS compose.original.yaml compose.candidate.yaml; do
  if [[ ! -f "$MAINTENANCE_BUNDLE/$path" ]]; then
    printf 'NPM maintenance bundle thiếu file: %s\n' "$path" >&2
    exit 66
  fi
  mode=$(stat -c '%a' "$MAINTENANCE_BUNDLE/$path")
  if ((8#$mode & 8#077)); then
    printf 'NPM maintenance file không private: %s (%s).\n' "$path" "$mode" >&2
    exit 78
  fi
done
for sensitive_path in "$COMPOSE_DIR/compose.yaml" "$COMPOSE_DIR/.env" \
  "$CRITICAL_MANIFEST"; do
  mode=$(stat -c '%a' "$sensitive_path")
  if ((8#$mode & 8#077)); then
    printf 'NPM production file không private: %s (%s).\n' \
      "$sensitive_path" "$mode" >&2
    exit 78
  fi
done
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  mode=$(stat -c '%a' "$EXCEPTION_MANIFEST")
  if ((8#$mode & 8#077)); then
    printf 'NPM route-exception file không private: %s.\n' "$mode" >&2
    exit 78
  fi
fi

(cd "$MAINTENANCE_BUNDLE" && sha256sum --check SHA256SUMS)
grep -Fxq 'BUNDLE_FORMAT=hyper-auth-nginx-proxy-manager-maintenance-v1' \
  "$MAINTENANCE_BUNDLE/METADATA.env"
read_metadata() {
  local key=$1
  grep -m1 "^${key}=" "$MAINTENANCE_BUNDLE/METADATA.env" | cut -d= -f2-
}
current_version=$(read_metadata CURRENT_VERSION)
current_image=$(read_metadata CURRENT_IMAGE)
current_image_id=$(read_metadata CURRENT_IMAGE_ID)
target_version=$(read_metadata TARGET_VERSION)
target_image=$(read_metadata TARGET_IMAGE)
target_image_id=$(read_metadata TARGET_IMAGE_ID)
backup_basename=$(read_metadata BACKUP_BASENAME)
for version in "$current_version" "$target_version"; do
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'NPM maintenance metadata có version không hợp lệ.' >&2
    exit 64
  fi
done
for image_ref in "$current_image" "$target_image"; do
  if [[ ! "$image_ref" =~ ^[a-z0-9./-]+@sha256:[0-9a-f]{64}$ ]]; then
    printf '%s\n' 'NPM maintenance metadata thiếu exact image digest.' >&2
    exit 64
  fi
done
for image_id in "$current_image_id" "$target_image_id"; do
  if [[ ! "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf '%s\n' 'NPM maintenance metadata thiếu exact image ID.' >&2
    exit 64
  fi
done
if [[ ! "$backup_basename" =~ ^npm-[0-9]{8}T[0-9]{6}Z$ ]] ||
  [[ ! -d "$BACKUP_ROOT/$backup_basename" ]]; then
  printf '%s\n' 'NPM rollback backup trong maintenance metadata không tồn tại.' >&2
  exit 66
fi
for backup_file in METADATA.env SHA256SUMS database-npm.sql \
  config-app-letsencrypt.tar.gz; do
  if [[ ! -f "$BACKUP_ROOT/$backup_basename/$backup_file" ]]; then
    printf 'NPM rollback backup thiếu file: %s\n' "$backup_file" >&2
    exit 66
  fi
done
(cd "$BACKUP_ROOT/$backup_basename" && sha256sum --check SHA256SUMS)

exec 9>"$BACKUP_ROOT/.upgrade-deploy.lock"
if ! flock -n 9; then
  printf '%s\n' 'Một NPM production upgrade khác đang chạy.' >&2
  exit 75
fi

cd "$COMPOSE_DIR"
docker compose config --quiet
if ! cmp -s compose.yaml "$MAINTENANCE_BUNDLE/compose.original.yaml"; then
  printf '%s\n' 'NPM production Compose đã drift khỏi maintenance bundle.' >&2
  exit 1
fi
docker compose --project-directory "$COMPOSE_DIR" \
  -f "$MAINTENANCE_BUNDLE/compose.candidate.yaml" \
  --env-file "$COMPOSE_DIR/.env" config --quiet
mapfile -t current_images < <(docker compose config --images)
mapfile -t candidate_images < <(
  docker compose --project-directory "$COMPOSE_DIR" \
    -f "$MAINTENANCE_BUNDLE/compose.candidate.yaml" \
    --env-file "$COMPOSE_DIR/.env" config --images
)
if [[ $(printf '%s\n' "${current_images[@]}" | grep -Fxc "$current_image") != 1 ]] ||
  [[ $(printf '%s\n' "${candidate_images[@]}" | grep -Fxc "$target_image") != 1 ]] ||
  printf '%s\n' "${current_images[@]}" | grep -Fxq "$target_image" ||
  printf '%s\n' "${candidate_images[@]}" | grep -Fxq "$current_image"; then
  printf '%s\n' 'NPM current/candidate image không khớp maintenance metadata.' >&2
  exit 1
fi
docker image inspect "$current_image_id" "$target_image_id" >/dev/null
if [[ $(docker image inspect "$current_image" --format '{{.Id}}') != "$current_image_id" ]] ||
  [[ $(docker image inspect "$target_image" --format '{{.Id}}') != "$target_image_id" ]]; then
  printf '%s\n' 'NPM image digest và image ID không khớp.' >&2
  exit 1
fi
if [[ $(docker inspect "$APP_CONTAINER" --format '{{.State.Running}}') != true ]] ||
  [[ $(docker inspect "$DB_CONTAINER" --format '{{.State.Running}}') != true ]] ||
  [[ $(docker inspect "$APP_CONTAINER" --format '{{.Image}}') != "$current_image_id" ]] ||
  [[ $(docker exec "$APP_CONTAINER" node -p \
    'require("/app/package.json").version') != "$current_version" ]]; then
  printf '%s\n' 'NPM production runtime không khớp trạng thái current đã duyệt.' >&2
  exit 1
fi

"$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
  --allow-production-nginx-proxy-manager-route-probe

compose_uid=$(stat -c '%u' compose.yaml)
compose_gid=$(stat -c '%g' compose.yaml)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
rollback_compose="$COMPOSE_DIR/compose.pre-npm-${current_version}-${stamp}.yaml"
candidate_tmp="$COMPOSE_DIR/.compose.npm-deploy.$$.yaml"
rollback_tmp="$COMPOSE_DIR/.compose.npm-rollback.$$.yaml"
cleanup() {
  find "$candidate_tmp" "$rollback_tmp" -maxdepth 0 -type f -delete 2>/dev/null || true
}
trap cleanup EXIT
if [[ -e "$rollback_compose" ]]; then
  printf '%s\n' 'NPM rollback Compose destination đã tồn tại.' >&2
  exit 1
fi
install -m 0600 "$MAINTENANCE_BUNDLE/compose.original.yaml" "$rollback_compose"
chown "$compose_uid:$compose_gid" "$rollback_compose"
install -m 0600 "$MAINTENANCE_BUNDLE/compose.candidate.yaml" "$candidate_tmp"
chown "$compose_uid:$compose_gid" "$candidate_tmp"
mv "$candidate_tmp" compose.yaml

wait_for_runtime() {
  local expected_id=$1
  local expected_version=$2
  local attempt
  for attempt in $(seq 1 120); do
    if [[ $(docker inspect "$APP_CONTAINER" --format '{{.State.Running}}' \
      2>/dev/null || true) == true ]] &&
      [[ $(docker inspect "$APP_CONTAINER" --format '{{.Image}}' \
        2>/dev/null || true) == "$expected_id" ]] &&
      [[ $(docker exec "$APP_CONTAINER" node -p \
        'require("/app/package.json").version' 2>/dev/null || true) == \
        "$expected_version" ]] &&
      docker exec "$APP_CONTAINER" node -e '
        require("http").get("http://127.0.0.1:81/api/", response => {
          response.resume();
          process.exit(response.statusCode === 200 ? 0 : 1);
        }).on("error", () => process.exit(1));
      ' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

set +e
(
  set -e
  docker compose config --quiet
  docker compose up -d --no-deps "$APP_SERVICE"
  wait_for_runtime "$target_image_id" "$target_version"
  docker exec "$APP_CONTAINER" nginx -t >/dev/null
  "$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
    --allow-production-nginx-proxy-manager-route-probe
)
deploy_status=$?
set -e

if ((deploy_status != 0)); then
  printf '%s\n' 'NPM post-upgrade gate fail; bắt đầu rollback exact Compose/image.' >&2
  rollback_status=0
  install -m 0600 "$rollback_compose" "$rollback_tmp" || rollback_status=$?
  if ((rollback_status == 0)); then
    chown "$compose_uid:$compose_gid" "$rollback_tmp" || rollback_status=$?
  fi
  if ((rollback_status == 0)); then
    mv "$rollback_tmp" compose.yaml || rollback_status=$?
  fi
  if ((rollback_status == 0)); then
    set +e
    (
      set -e
      docker compose config --quiet
      docker compose up -d --no-deps "$APP_SERVICE"
      wait_for_runtime "$current_image_id" "$current_version"
      docker exec "$APP_CONTAINER" nginx -t >/dev/null
      "$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
        --allow-production-nginx-proxy-manager-route-probe
    )
    rollback_status=$?
    set -e
  fi
  if ((rollback_status != 0)); then
    printf '%s\n' 'CRITICAL: NPM automatic rollback không vượt runtime/route gate.' >&2
    exit 70
  fi
  printf 'NPM rollback pass: version %s và public route baseline đã khôi phục.\n' \
    "$current_version" >&2
  exit "$deploy_status"
fi

trap - EXIT
cleanup
printf 'NPM production upgrade pass: %s -> %s.\n' \
  "$current_version" "$target_version"
printf 'Rollback Compose giữ mode 0600 tại: %s\n' "$rollback_compose"
printf '%s\n' 'Nginx syntax, internal API và full redacted public-route matrix đều pass.'
