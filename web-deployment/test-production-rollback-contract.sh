#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DRILL="$ROOT/web-deployment/rehearse-production-rollback.sh"

bash -n "$DRILL"

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ha-web-rollback-contract.XXXXXX")
cleanup() {
  rm -rf -- "$temp_dir"
}
trap cleanup EXIT INT TERM

stack_dir="$temp_dir/stack"
fake_bin="$temp_dir/bin"
fake_state="$temp_dir/state"
mkdir -p "$stack_dir" "$fake_bin" "$fake_state"

current_image='hyper-authenticator-web:1.1.0-abcdef1'
previous_image='hyper-authenticator-web:1.1.0-1234567'
current_body='TEST_ONLY_CURRENT_WEB_ARTIFACT'
previous_body='TEST_ONLY_PREVIOUS_WEB_ARTIFACT'
current_hash=$(printf '%s' "$current_body" | sha256sum | awk '{print $1}')
previous_hash=$(printf '%s' "$previous_body" | sha256sum | awk '{print $1}')

cat >"$stack_dir/.env" <<EOF
WEB_IMAGE=$current_image
SUPABASE_URL=https://supabase.test.invalid
EOF
chmod 600 "$stack_dir/.env"
printf '%s\n' 'TEST_ONLY compose fixture' >"$stack_dir/compose.yml"
printf '%s' "$current_image" >"$fake_state/live-image"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

hash_for_image() {
  case "$1" in
    "$FAKE_CURRENT_IMAGE") printf '%s' "$FAKE_CURRENT_HASH" ;;
    "$FAKE_PREVIOUS_IMAGE") printf '%s' "$FAKE_PREVIOUS_HASH" ;;
    *) exit 1 ;;
  esac
}

image_for_container() {
  local name=$1
  if [[ "$name" == hyper-authenticator-web ]]; then
    cat "$FAKE_STATE_DIR/live-image"
  else
    cat "$FAKE_STATE_DIR/container-$name"
  fi
}

case "${1:-}" in
  image)
    [[ "${2:-}" == inspect ]]
    image=${3:?}
    format=${5:?}
    case "$format" in
      '{{.Architecture}}') printf '%s\n' amd64 ;;
      '{{.Id}}') printf 'sha256:%064d\n' 1 ;;
      *) exit 1 ;;
    esac
    ;;
  inspect)
    name=${2:?}
    format=${4:?}
    case "$format" in
      '{{.State.Health.Status}}') printf '%s\n' healthy ;;
      '{{.Config.Image}}') image_for_container "$name" ;;
      *) exit 1 ;;
    esac
    ;;
  run)
    if [[ " $* " == *' --detach '* ]]; then
      name=''
      previous=''
      for argument in "$@"; do
        if [[ "$previous" == --name ]]; then
          name=$argument
        fi
        previous=$argument
      done
      image=${!#}
      printf '%s' "$image" >"$FAKE_STATE_DIR/container-$name"
      printf '%s\n' fake-container-id
    else
      image=${@: -2:1}
      printf '%s  /usr/share/nginx/html/main.dart.js\n' "$(hash_for_image "$image")"
    fi
    ;;
  exec)
    name=${2:?}
    image=$(image_for_container "$name")
    if [[ " $* " == *' sha256sum '* ]]; then
      printf '%s  /usr/share/nginx/html/main.dart.js\n' "$(hash_for_image "$image")"
    elif [[ " $* " == *'/healthz'* ]]; then
      printf '%s\n' healthy
    else
      printf '%s\n' '<title>Hyper Authenticator</title>'
    fi
    ;;
  container)
    [[ "${2:-}" == rm ]]
    name=${!#}
    rm -f -- "$FAKE_STATE_DIR/container-$name"
    ;;
  compose)
    shift
    action=''
    for argument in "$@"; do
      case "$argument" in
        config | up) action=$argument; break ;;
      esac
    done
    if [[ "$action" == config && " $* " == *' --images '* ]]; then
      awk -F= '$1 == "WEB_IMAGE" { print $2 }' "$FAKE_ENV_FILE"
    elif [[ "$action" == config ]]; then
      exit 0
    elif [[ "$action" == up ]]; then
      image=$(awk -F= '$1 == "WEB_IMAGE" { print $2 }' "$FAKE_ENV_FILE")
      printf '%s' "$image" >"$FAKE_STATE_DIR/live-image"
      printf '%s\n' "$image" >>"$FAKE_STATE_DIR/transitions"
    else
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url=${!#}
image=$(cat "$FAKE_STATE_DIR/live-image")
if [[ "$image" == "$FAKE_PREVIOUS_IMAGE" && "${FAIL_PREVIOUS_PUBLIC:-false}" == true && \
  "$url" == *'/main.dart.js?'* ]]; then
  exit 22
fi

if [[ " $* " == *' -fsSI '* ]]; then
  printf '%s\n' \
    'HTTP/2 200' \
    'strict-transport-security: max-age=31536000' \
    'content-security-policy: default-src self' \
    'cache-control: no-store'
elif [[ "$url" == *'/main.dart.js?'* ]]; then
  if [[ "$image" == "$FAKE_CURRENT_IMAGE" ]]; then
    printf '%s' "$FAKE_CURRENT_BODY"
  else
    printf '%s' "$FAKE_PREVIOUS_BODY"
  fi
elif [[ "$url" == *'/healthz' ]]; then
  printf '%s\n' healthy
else
  printf '%s\n' '<title>Hyper Authenticator</title>'
fi
EOF
chmod 700 "$fake_bin/docker" "$fake_bin/curl"

run_drill() {
  env \
    "PATH=$fake_bin:$PATH" \
    "FAKE_STATE_DIR=$fake_state" \
    "FAKE_ENV_FILE=$stack_dir/.env" \
    "FAKE_CURRENT_IMAGE=$current_image" \
    "FAKE_PREVIOUS_IMAGE=$previous_image" \
    "FAKE_CURRENT_HASH=$current_hash" \
    "FAKE_PREVIOUS_HASH=$previous_hash" \
    "FAKE_CURRENT_BODY=$current_body" \
    "FAKE_PREVIOUS_BODY=$previous_body" \
    "FAIL_PREVIOUS_PUBLIC=${FAIL_PREVIOUS_PUBLIC:-false}" \
    "STACK_DIR=$stack_dir" \
    "COMPOSE_FILE=$stack_dir/compose.yml" \
    "ENV_FILE=$stack_dir/.env" \
    'PUBLIC_ORIGIN=https://authenticator.test.invalid' \
    'EXPECTED_ARCH=amd64' \
    'HEALTH_TIMEOUT_SECONDS=2' \
    "EVIDENCE_DIR=$stack_dir/.rollback-drill" \
    "EVIDENCE_FILE=$stack_dir/.rollback-drill/last-success.env" \
    "$@"
}

if run_drill "$DRILL" \
  "$current_image" "$current_hash" "$previous_image" "$previous_hash" \
  WRONG_CONFIRMATION >/dev/null 2>&1; then
  printf '%s\n' 'Sai confirmation phải bị từ chối.' >&2
  exit 1
fi
[[ $(cat "$fake_state/live-image") == "$current_image" ]]
[[ ! -e "$stack_dir/.rollback-drill/last-success.env" ]]

if run_drill "$DRILL" \
  'hyper-authenticator-web:latest' "$current_hash" "$previous_image" "$previous_hash" \
  RUN_LIVE_WEB_ROLLBACK_DRILL >/dev/null 2>&1; then
  printf '%s\n' 'Floating image tag phải bị từ chối.' >&2
  exit 1
fi
if run_drill "$DRILL" \
  "$current_image" "$current_hash" "$previous_image" \
  0000000000000000000000000000000000000000000000000000000000000000 \
  RUN_LIVE_WEB_ROLLBACK_DRILL >/dev/null 2>&1; then
  printf '%s\n' 'Image JS hash sai phải bị từ chối ở preflight.' >&2
  exit 1
fi
[[ $(cat "$fake_state/live-image") == "$current_image" ]]
[[ ! -e "$stack_dir/.rollback-drill/last-success.env" ]]

run_drill "$DRILL" \
  "$current_image" "$current_hash" "$previous_image" "$previous_hash" \
  RUN_LIVE_WEB_ROLLBACK_DRILL >/dev/null

[[ $(cat "$fake_state/live-image") == "$current_image" ]]
grep -qx "WEB_IMAGE=$current_image" "$stack_dir/.env"
[[ $(sed -n '1p' "$fake_state/transitions") == "$previous_image" ]]
[[ $(sed -n '2p' "$fake_state/transitions") == "$current_image" ]]
evidence="$stack_dir/.rollback-drill/last-success.env"
[[ -f "$evidence" && ! -L "$evidence" ]]
grep -qx "current_image=$current_image" "$evidence"
grep -qx "previous_image=$previous_image" "$evidence"
if mode=$(stat -c '%a' "$evidence" 2>/dev/null); then
  :
else
  mode=$(stat -f '%Lp' "$evidence")
fi
[[ "$mode" == 600 ]]
cp "$evidence" "$temp_dir/evidence-before-failure"

: >"$fake_state/transitions"
if FAIL_PREVIOUS_PUBLIC=true run_drill "$DRILL" \
  "$current_image" "$current_hash" "$previous_image" "$previous_hash" \
  RUN_LIVE_WEB_ROLLBACK_DRILL >/dev/null 2>"$temp_dir/failure.log"; then
  printf '%s\n' 'Public verify failure phải làm drill fail.' >&2
  exit 1
fi
[[ $(cat "$fake_state/live-image") == "$current_image" ]]
grep -qx "WEB_IMAGE=$current_image" "$stack_dir/.env"
cmp -s "$evidence" "$temp_dir/evidence-before-failure"
grep -Fq 'Auto-restore original Web release pass.' "$temp_dir/failure.log"

printf '%s\n' \
  'Web rollback contract pass: confirmation, rollback/forward và failure auto-restore.'
