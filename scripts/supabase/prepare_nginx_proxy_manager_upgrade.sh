#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR=${1:-/opt/stacks/nginx-proxy-manager-app}
BACKUP_ROOT=${2:-/home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager}
PIN_FILE=${3:-}
CRITICAL_MANIFEST=${4:-}
EXCEPTION_MANIFEST=${5:--}
CONFIRMATION=${6:-}
APP_CONTAINER=${NPM_APP_CONTAINER:-nginx-proxy-manager-app}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BACKUP_SCRIPT=${NPM_BACKUP_SCRIPT:-$SCRIPT_DIR/backup_nginx_proxy_manager.sh}
RESTORE_SCRIPT=${NPM_RESTORE_SCRIPT:-$SCRIPT_DIR/rehearse_nginx_proxy_manager_backup.sh}
CANARY_SCRIPT=${NPM_CANARY_SCRIPT:-$SCRIPT_DIR/rehearse_nginx_proxy_manager_upgrade.sh}
ROUTE_SCRIPT=${NPM_ROUTE_SCRIPT:-$SCRIPT_DIR/test_nginx_proxy_manager_route_matrix.sh}

if [[ -z "$PIN_FILE" || -z "$CRITICAL_MANIFEST" ||
  "$CONFIRMATION" != '--allow-nginx-proxy-manager-upgrade-preparation' ]]; then
  printf '%s\n' \
    'Usage: prepare_nginx_proxy_manager_upgrade.sh COMPOSE_DIR BACKUP_ROOT PIN_FILE CRITICAL_MANIFEST EXCEPTION_MANIFEST|- --allow-nginx-proxy-manager-upgrade-preparation' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM upgrade preparation chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
for command_name in awk basename cat cmp cut date docker find flock grep install \
  mktemp mv realpath sed sha256sum sort stat tail; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu NPM upgrade-preparation dependency: %s\n' "$command_name" >&2
    exit 69
  fi
done
for script_path in "$BACKUP_SCRIPT" "$RESTORE_SCRIPT" "$CANARY_SCRIPT" \
  "$ROUTE_SCRIPT"; do
  if [[ ! -x "$script_path" ]]; then
    printf 'Thiếu executable NPM preparation harness: %s\n' "$script_path" >&2
    exit 66
  fi
done
if [[ ! -d "$COMPOSE_DIR" || ! -f "$COMPOSE_DIR/compose.yaml" ||
  ! -f "$COMPOSE_DIR/.env" || ! -f "$PIN_FILE" ||
  ! -f "$CRITICAL_MANIFEST" ]]; then
  printf '%s\n' 'NPM upgrade-preparation input không đầy đủ.' >&2
  exit 66
fi

COMPOSE_DIR=$(realpath "$COMPOSE_DIR")
BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
PIN_FILE=$(realpath "$PIN_FILE")
CRITICAL_MANIFEST=$(realpath "$CRITICAL_MANIFEST")
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  EXCEPTION_MANIFEST=$(realpath "$EXCEPTION_MANIFEST")
fi

for sensitive_path in "$COMPOSE_DIR/compose.yaml" "$COMPOSE_DIR/.env" \
  "$CRITICAL_MANIFEST"; do
  mode=$(stat -c '%a' "$sensitive_path")
  if ((8#$mode & 8#077)); then
    printf 'NPM preparation sensitive file không private: %s.\n' "$mode" >&2
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

read_pin() {
  local key=$1
  grep -m1 "^${key}=" "$PIN_FILE" | cut -d= -f2-
}
current_version=$(read_pin NPM_VERSION)
current_image=$(read_pin NPM_IMAGE)
target_version=$(read_pin REVIEWED_NPM_TARGET)
target_image=$(read_pin REVIEWED_NPM_TARGET_IMAGE)
for version in "$current_version" "$target_version"; do
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'NPM preparation pin có version không hợp lệ.' >&2
    exit 64
  fi
done
for image_ref in "$current_image" "$target_image"; do
  if [[ ! "$image_ref" =~ ^[a-z0-9./-]+@sha256:[0-9a-f]{64}$ ]]; then
    printf '%s\n' 'NPM preparation pin thiếu exact image digest.' >&2
    exit 64
  fi
done
if [[ "$current_image" == "$target_image" || "$current_version" == "$target_version" ]]; then
  printf '%s\n' 'NPM preparation current và target không được giống nhau.' >&2
  exit 64
fi

umask 077
install -d -m 0700 "$BACKUP_ROOT"
exec 9>"$BACKUP_ROOT/.upgrade-prepare.lock"
if ! flock -n 9; then
  printf '%s\n' 'Một NPM upgrade preparation khác đang chạy.' >&2
  exit 75
fi

cd "$COMPOSE_DIR"
docker compose config --quiet
mapfile -t compose_images < <(docker compose config --images)
if [[ $(printf '%s\n' "${compose_images[@]}" | grep -Fxc "$current_image") != 1 ]] ||
  printf '%s\n' "${compose_images[@]}" | grep -Fxq "$target_image"; then
  printf '%s\n' 'NPM production Compose không khớp exact current pin.' >&2
  exit 1
fi
if [[ $(docker inspect "$APP_CONTAINER" --format '{{.State.Running}}') != true ]]; then
  printf '%s\n' 'NPM production app container không chạy.' >&2
  exit 1
fi
runtime_image_id=$(docker inspect "$APP_CONTAINER" --format '{{.Image}}')
current_image_id=$(docker image inspect "$current_image" --format '{{.Id}}')
target_image_id=$(docker image inspect "$target_image" --format '{{.Id}}')
if [[ "$runtime_image_id" != "$current_image_id" ]]; then
  printf '%s\n' 'NPM runtime image không khớp current pin.' >&2
  exit 1
fi
runtime_version=$(docker exec "$APP_CONTAINER" node -p \
  'require("/app/package.json").version')
if [[ "$runtime_version" != "$current_version" ]]; then
  printf '%s\n' 'NPM runtime version không khớp current pin.' >&2
  exit 1
fi

"$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
  --allow-production-nginx-proxy-manager-route-probe

backup_log=$(mktemp "${TMPDIR:-/tmp}/hyper-auth-npm-prepare-backup.XXXXXX")
candidate_tmp="$COMPOSE_DIR/.compose.npm-upgrade-candidate.$$.yaml"
work_dir=''
cleanup() {
  find "$backup_log" -maxdepth 0 -type f -delete 2>/dev/null || true
  find "$candidate_tmp" -maxdepth 0 -type f -delete 2>/dev/null || true
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    find "$work_dir" -depth -delete
  fi
}
trap cleanup EXIT

"$BACKUP_SCRIPT" "$COMPOSE_DIR" "$BACKUP_ROOT" \
  --allow-nginx-proxy-manager-backup >"$backup_log"
backup_dir=$(sed -n 's/^NPM production backup pass: //p' "$backup_log" | tail -1)
if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
  printf '%s\n' 'NPM preparation không xác định được fresh backup.' >&2
  exit 1
fi
backup_dir=$(realpath "$backup_dir")
grep -E '^(NPM production backup pass:|Transactional DB dump)' "$backup_log"

"$RESTORE_SCRIPT" "$backup_dir" \
  --allow-isolated-nginx-proxy-manager-restore
"$CANARY_SCRIPT" "$backup_dir" "$target_image_id" "$target_version" \
  --allow-isolated-nginx-proxy-manager-upgrade
"$ROUTE_SCRIPT" "$CRITICAL_MANIFEST" "$EXCEPTION_MANIFEST" \
  --allow-production-nginx-proxy-manager-route-probe

stamp=$(date -u +%Y%m%dT%H%M%SZ)
final_dir="$BACKUP_ROOT/maintenance-npm-$stamp"
work_dir="$BACKUP_ROOT/.maintenance-npm-$stamp.tmp.$$"
if [[ -e "$final_dir" || -e "$work_dir" ]]; then
  printf '%s\n' 'NPM maintenance-bundle destination đã tồn tại.' >&2
  exit 1
fi
install -d -m 0700 "$work_dir"
install -m 0600 "$COMPOSE_DIR/compose.yaml" "$work_dir/compose.original.yaml"

awk -v from="$current_image" -v to="$target_image" '
  {
    position = index($0, from)
    if (position > 0) {
      $0 = substr($0, 1, position - 1) to substr($0, position + length(from))
      replacements++
    }
    print
  }
  END { if (replacements != 1) exit 42 }
' "$COMPOSE_DIR/compose.yaml" >"$candidate_tmp"
chmod 0600 "$candidate_tmp"

current_resolved="$work_dir/current.resolved.yaml"
candidate_resolved="$work_dir/candidate.resolved.yaml"
candidate_normalized="$work_dir/candidate.normalized.yaml"
docker compose --project-directory "$COMPOSE_DIR" \
  -f "$COMPOSE_DIR/compose.yaml" --env-file "$COMPOSE_DIR/.env" \
  config >"$current_resolved"
docker compose --project-directory "$COMPOSE_DIR" \
  -f "$candidate_tmp" --env-file "$COMPOSE_DIR/.env" \
  config >"$candidate_resolved"
awk -v from="$target_image" -v to="$current_image" '
  {
    position = index($0, from)
    if (position > 0) {
      $0 = substr($0, 1, position - 1) to substr($0, position + length(from))
      replacements++
    }
    print
  }
  END { if (replacements != 1) exit 42 }
' "$candidate_resolved" >"$candidate_normalized"
if ! cmp -s "$current_resolved" "$candidate_normalized"; then
  printf '%s\n' 'NPM candidate thay đổi ngoài exact app image.' >&2
  exit 1
fi
find "$current_resolved" "$candidate_resolved" "$candidate_normalized" \
  -maxdepth 0 -type f -delete
mv "$candidate_tmp" "$work_dir/compose.candidate.yaml"

cat >"$work_dir/METADATA.env" <<EOF
BUNDLE_FORMAT=hyper-auth-nginx-proxy-manager-maintenance-v1
CREATED_AT=$stamp
BACKUP_BASENAME=$(basename "$backup_dir")
CURRENT_VERSION=$current_version
CURRENT_IMAGE=$current_image
CURRENT_IMAGE_ID=$current_image_id
TARGET_VERSION=$target_version
TARGET_IMAGE=$target_image
TARGET_IMAGE_ID=$target_image_id
CRITICAL_MANIFEST_SHA256=$(sha256sum "$CRITICAL_MANIFEST" | awk '{print $1}')
EXCEPTION_MANIFEST_SHA256=$(
  if [[ "$EXCEPTION_MANIFEST" == '-' ]]; then printf 'none';
  else sha256sum "$EXCEPTION_MANIFEST" | awk '{print $1}'; fi
)
EOF
find "$work_dir" -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' |
  LC_ALL=C sort |
  while IFS= read -r name; do
    (cd "$work_dir" && sha256sum "$name")
  done >"$work_dir/SHA256SUMS"
(cd "$work_dir" && sha256sum --check SHA256SUMS)
find "$work_dir" -type d -exec chmod 0700 {} +
find "$work_dir" -type f -exec chmod 0600 {} +
mv "$work_dir" "$final_dir"
work_dir=''
if ! (cd "$final_dir" && sha256sum --check SHA256SUMS); then
  printf '%s\n' 'NPM maintenance bundle post-move checksum fail.' >&2
  exit 1
fi
trap - EXIT
find "$backup_log" -maxdepth 0 -type f -delete

printf 'NPM upgrade preparation pass: %s\n' "$final_dir"
printf 'Fresh rollback backup: %s\n' "$backup_dir"
printf '%s\n' \
  'Candidate chỉ đổi exact NPM image; production Compose/container chưa bị thay đổi.'
