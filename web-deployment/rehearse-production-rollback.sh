#!/usr/bin/env bash
set -euo pipefail

CURRENT_IMAGE=${1:?Usage: rehearse-production-rollback.sh CURRENT_IMAGE CURRENT_JS_SHA256 PREVIOUS_IMAGE PREVIOUS_JS_SHA256 CONFIRMATION}
CURRENT_JS_SHA256=${2:?Usage: rehearse-production-rollback.sh CURRENT_IMAGE CURRENT_JS_SHA256 PREVIOUS_IMAGE PREVIOUS_JS_SHA256 CONFIRMATION}
PREVIOUS_IMAGE=${3:?Usage: rehearse-production-rollback.sh CURRENT_IMAGE CURRENT_JS_SHA256 PREVIOUS_IMAGE PREVIOUS_JS_SHA256 CONFIRMATION}
PREVIOUS_JS_SHA256=${4:?Usage: rehearse-production-rollback.sh CURRENT_IMAGE CURRENT_JS_SHA256 PREVIOUS_IMAGE PREVIOUS_JS_SHA256 CONFIRMATION}
CONFIRMATION=${5:?Usage: rehearse-production-rollback.sh CURRENT_IMAGE CURRENT_JS_SHA256 PREVIOUS_IMAGE PREVIOUS_JS_SHA256 CONFIRMATION}

STACK_DIR=${STACK_DIR:-/opt/stacks/hyper-authenticator-web}
COMPOSE_FILE=${COMPOSE_FILE:-$STACK_DIR/compose.yml}
ENV_FILE=${ENV_FILE:-$STACK_DIR/.env}
PUBLIC_ORIGIN=${PUBLIC_ORIGIN:-https://authenticator.hyperz.xyz}
EXPECTED_ARCH=${EXPECTED_ARCH:-amd64}
HEALTH_TIMEOUT_SECONDS=${HEALTH_TIMEOUT_SECONDS:-120}
EVIDENCE_DIR=${EVIDENCE_DIR:-$STACK_DIR/.rollback-drill}
EVIDENCE_FILE=${EVIDENCE_FILE:-$EVIDENCE_DIR/last-success.env}

umask 077

confirmation_contract='RUN_LIVE_WEB_ROLLBACK_DRILL'
container_name='hyper-authenticator-web'
shadow_name=''
rollback_env=''
env_tmp=''
mutated=false
completed=false

fail() {
  printf 'Web rollback drill thất bại: %s\n' "$1" >&2
  exit 1
}

require_image() {
  local image=$1
  [[ "$image" =~ ^hyper-authenticator-web:[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]{7,40}$ ]] || \
    fail 'image phải pin semantic version và commit hex; floating tag bị từ chối.'
}

require_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]] || fail 'main.dart.js SHA-256 không hợp lệ.'
}

file_mode() {
  if stat -c '%a' "$1" 2>/dev/null; then
    return
  fi
  stat -f '%Lp' "$1"
}

read_env_field() {
  local key=$1
  local value
  value=$(awk -F= -v key="$key" '
    $1 == key {
      count += 1
      value = substr($0, index($0, "=") + 1)
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' "$ENV_FILE") || fail "$key thiếu hoặc lặp trong deployment env."
  case "$value" in
    \"*\") value=${value:1:${#value}-2} ;;
    \'*\') value=${value:1:${#value}-2} ;;
  esac
  [[ -n "$value" ]] || fail "$key rỗng trong deployment env."
  printf '%s' "$value"
}

image_arch() {
  docker image inspect "$1" --format '{{.Architecture}}'
}

image_id() {
  docker image inspect "$1" --format '{{.Id}}'
}

image_js_sha256() {
  docker run --rm --entrypoint sha256sum "$1" \
    /usr/share/nginx/html/main.dart.js | awk '{print $1}'
}

cleanup_shadow() {
  if [[ -n "$shadow_name" ]]; then
    docker container rm -f "$shadow_name" >/dev/null 2>&1 || true
    shadow_name=''
  fi
}

wait_container_healthy() {
  local name=$1
  local elapsed=0
  local health=''
  while ((elapsed < HEALTH_TIMEOUT_SECONDS)); do
    health=$(docker inspect "$name" --format '{{.State.Health.Status}}' 2>/dev/null || true)
    [[ "$health" == healthy ]] && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

preflight_image() {
  local image=$1
  local expected_hash=$2
  local phase=$3
  local actual_hash

  [[ "$(image_arch "$image")" == "$EXPECTED_ARCH" ]] || \
    fail "$phase image sai architecture."
  actual_hash=$(image_js_sha256 "$image")
  [[ "$actual_hash" == "$expected_hash" ]] || fail "$phase image JS hash không khớp."

  shadow_name="ha-web-rollback-${phase}-$$"
  docker run --detach --name "$shadow_name" \
    --read-only \
    --tmpfs /tmp:size=1m,mode=1777 \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --env "SUPABASE_URL=$supabase_url" \
    "$image" >/dev/null
  wait_container_healthy "$shadow_name" || fail "$phase shadow container không healthy."
  docker exec "$shadow_name" wget -q -O - http://127.0.0.1:8080/healthz | \
    grep -qx healthy
  docker exec "$shadow_name" wget -q -O - http://127.0.0.1:8080/settings | \
    grep -Fq '<title>Hyper Authenticator</title>'
  actual_hash=$(docker exec "$shadow_name" sha256sum \
    /usr/share/nginx/html/main.dart.js | awk '{print $1}')
  [[ "$actual_hash" == "$expected_hash" ]] || fail "$phase shadow JS hash không khớp."
  cleanup_shadow
}

set_web_image() {
  local image=$1
  env_tmp=$(mktemp "$STACK_DIR/.env.next.XXXXXX")
  if ! awk -v image="$image" '
    /^WEB_IMAGE=/ {
      count += 1
      print "WEB_IMAGE=" image
      next
    }
    { print }
    END { if (count != 1) exit 42 }
  ' "$ENV_FILE" >"$env_tmp"; then
    fail 'không thể thay exact WEB_IMAGE trong deployment env.'
  fi
  chmod 600 "$env_tmp"
  mv -f "$env_tmp" "$ENV_FILE"
  env_tmp=''
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet
}

wait_public_hash() {
  local expected_hash=$1
  local elapsed=0
  local actual_hash=''
  while ((elapsed < HEALTH_TIMEOUT_SECONDS)); do
    actual_hash=$(curl --proto '=https' --tlsv1.2 --connect-timeout 5 --max-time 15 \
      -fsS "$PUBLIC_ORIGIN/main.dart.js?rollback_drill=$(date +%s)" 2>/dev/null | \
      sha256sum | awk '{print $1}' || true)
    [[ "$actual_hash" == "$expected_hash" ]] && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

verify_public() {
  local expected_hash=$1
  local health_body
  local headers
  local route

  wait_public_hash "$expected_hash" || fail 'public main.dart.js không chuyển tới exact expected hash.'
  health_body=$(curl --proto '=https' --tlsv1.2 --connect-timeout 5 --max-time 15 \
    -fsS "$PUBLIC_ORIGIN/healthz")
  [[ "$health_body" == healthy ]] || fail 'public health body không hợp lệ.'
  headers=$(curl --proto '=https' --tlsv1.2 --connect-timeout 5 --max-time 15 \
    -fsSI "$PUBLIC_ORIGIN/")
  printf '%s' "$headers" | grep -Fiq 'strict-transport-security:'
  printf '%s' "$headers" | grep -Fiq 'content-security-policy:'
  printf '%s' "$headers" | grep -Fiq 'cache-control: no-store'
  for route in / /settings /login /register /privacy; do
    curl --proto '=https' --tlsv1.2 --connect-timeout 5 --max-time 15 \
      -fsS "$PUBLIC_ORIGIN$route" | grep -Fq '<title>Hyper Authenticator</title>'
  done
}

verify_live() {
  local expected_image=$1
  local expected_hash=$2
  local actual_image
  local actual_hash

  wait_container_healthy "$container_name" || fail 'live container không healthy trong timeout.'
  actual_image=$(docker inspect "$container_name" --format '{{.Config.Image}}')
  [[ "$actual_image" == "$expected_image" ]] || fail 'live container không dùng expected image.'
  actual_hash=$(docker exec "$container_name" sha256sum \
    /usr/share/nginx/html/main.dart.js | awk '{print $1}')
  [[ "$actual_hash" == "$expected_hash" ]] || fail 'live container JS hash không khớp.'
  verify_public "$expected_hash"
}

restore_original() {
  local restore_ok=true
  local restore_tmp=''
  set +e
  cleanup_shadow
  if [[ -n "$env_tmp" ]]; then
    rm -f -- "$env_tmp"
    env_tmp=''
  fi
  if [[ -n "$rollback_env" && -f "$rollback_env" ]]; then
    restore_tmp=$(mktemp "$STACK_DIR/.env.restore.XXXXXX")
    cp "$rollback_env" "$restore_tmp"
    chmod 600 "$restore_tmp"
    mv -f "$restore_tmp" "$ENV_FILE"
  else
    restore_ok=false
  fi
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build >/dev/null || \
    restore_ok=false
  wait_container_healthy "$container_name" || restore_ok=false
  (verify_live "$CURRENT_IMAGE" "$CURRENT_JS_SHA256") || restore_ok=false
  set -e
  if [[ "$restore_ok" == true ]]; then
    printf '%s\n' 'Auto-restore original Web release pass.' >&2
    return 0
  fi
  printf '%s\n' 'CRITICAL: auto-restore original Web release không xác minh được.' >&2
  return 1
}

on_exit() {
  local exit_code=$?
  trap - EXIT INT TERM
  cleanup_shadow
  if [[ -n "$env_tmp" ]]; then
    rm -f -- "$env_tmp"
  fi
  if [[ "$mutated" == true && "$completed" != true ]]; then
    if ! restore_original; then
      exit 2
    fi
  fi
  exit "$exit_code"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "$CONFIRMATION" == "$confirmation_contract" ]] || \
  fail "confirmation phải đúng $confirmation_contract."
require_image "$CURRENT_IMAGE"
require_image "$PREVIOUS_IMAGE"
require_sha256 "$CURRENT_JS_SHA256"
require_sha256 "$PREVIOUS_JS_SHA256"
[[ "$CURRENT_IMAGE" != "$PREVIOUS_IMAGE" ]] || fail 'current và previous image phải khác nhau.'
[[ "$CURRENT_JS_SHA256" != "$PREVIOUS_JS_SHA256" ]] || fail 'hai JS hash phải khác nhau để drill quan sát được.'
[[ "$EXPECTED_ARCH" == amd64 || "$EXPECTED_ARCH" == arm64 ]] || fail 'expected architecture không hợp lệ.'
[[ "$HEALTH_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || fail 'health timeout không hợp lệ.'
[[ "$PUBLIC_ORIGIN" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] || fail 'public origin không hợp lệ.'
[[ -d "$STACK_DIR" && ! -L "$STACK_DIR" ]] || fail 'stack directory thiếu hoặc là symlink.'
[[ -f "$COMPOSE_FILE" && ! -L "$COMPOSE_FILE" ]] || fail 'compose file thiếu hoặc là symlink.'
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || fail 'deployment env thiếu hoặc là symlink.'
[[ "$(file_mode "$ENV_FILE")" == 600 ]] || fail 'deployment env phải có mode 0600.'

for command in awk curl docker grep mktemp mv sha256sum stat; do
  command -v "$command" >/dev/null 2>&1 || fail "thiếu command $command."
done

supabase_url=$(read_env_field SUPABASE_URL)
[[ "$supabase_url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]] || \
  fail 'SUPABASE_URL trong deployment env không phải HTTPS origin.'

configured_image=$(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --images)
[[ "$configured_image" == "$CURRENT_IMAGE" ]] || fail 'compose không ở exact current image trước drill.'
[[ "$(docker inspect "$container_name" --format '{{.Config.Image}}')" == "$CURRENT_IMAGE" ]] || \
  fail 'live container không ở exact current image trước drill.'
verify_live "$CURRENT_IMAGE" "$CURRENT_JS_SHA256"

preflight_image "$CURRENT_IMAGE" "$CURRENT_JS_SHA256" current
preflight_image "$PREVIOUS_IMAGE" "$PREVIOUS_JS_SHA256" previous

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
rollback_env=$(mktemp "$STACK_DIR/.env.rollback-drill-$timestamp.XXXXXX")
cp "$ENV_FILE" "$rollback_env"
chmod 600 "$rollback_env"

mutated=true
set_web_image "$PREVIOUS_IMAGE"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build >/dev/null
verify_live "$PREVIOUS_IMAGE" "$PREVIOUS_JS_SHA256"

set_web_image "$CURRENT_IMAGE"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build >/dev/null
verify_live "$CURRENT_IMAGE" "$CURRENT_JS_SHA256"

mkdir -p "$EVIDENCE_DIR"
[[ -d "$EVIDENCE_DIR" && ! -L "$EVIDENCE_DIR" ]] || fail 'evidence directory không hợp lệ.'
[[ ! -L "$EVIDENCE_FILE" ]] || fail 'evidence file không được là symlink.'
chmod 700 "$EVIDENCE_DIR"
evidence_tmp=$(mktemp "$EVIDENCE_DIR/.last-success.XXXXXX")
cat >"$evidence_tmp" <<EOF
format_version=1
completed_at_epoch=$(date +%s)
completed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
current_image=$CURRENT_IMAGE
current_image_id=$(image_id "$CURRENT_IMAGE")
current_js_sha256=$CURRENT_JS_SHA256
previous_image=$PREVIOUS_IMAGE
previous_image_id=$(image_id "$PREVIOUS_IMAGE")
previous_js_sha256=$PREVIOUS_JS_SHA256
EOF
chmod 600 "$evidence_tmp"
mv -f "$evidence_tmp" "$EVIDENCE_FILE"
[[ "$(file_mode "$EVIDENCE_FILE")" == 600 ]] || fail 'evidence file không giữ mode 0600.'
grep -qx 'format_version=1' "$EVIDENCE_FILE"
grep -qx "current_image=$CURRENT_IMAGE" "$EVIDENCE_FILE"
grep -qx "current_js_sha256=$CURRENT_JS_SHA256" "$EVIDENCE_FILE"
grep -qx "previous_image=$PREVIOUS_IMAGE" "$EVIDENCE_FILE"
grep -qx "previous_js_sha256=$PREVIOUS_JS_SHA256" "$EVIDENCE_FILE"

completed=true
printf 'Web production rollback drill pass: previous %s → current %s.\n' \
  "$PREVIOUS_IMAGE" "$CURRENT_IMAGE"
