#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${1:-.env}
BASE_URL=${2:-}
TOTAL_REQUESTS=${LOAD_TOTAL_REQUESTS:-100}
CONCURRENCY=${LOAD_CONCURRENCY:-10}
MAX_P95_MS=${LOAD_MAX_P95_MS:-1000}
MAX_SINGLE_MS=${LOAD_MAX_SINGLE_MS:-2000}
BATCH_INTERVAL_MS=${LOAD_BATCH_INTERVAL_MS:-0}

if [[ ! -f "$ENV_FILE" ]]; then
  printf 'Không tìm thấy Supabase env file: %s\n' "$ENV_FILE" >&2
  exit 66
fi

for command_name in awk curl date grep sort; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu command bắt buộc: %s\n' "$command_name" >&2
    exit 69
  fi
done

for value_name in TOTAL_REQUESTS CONCURRENCY MAX_P95_MS MAX_SINGLE_MS; do
  value=${!value_name}
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s phải là số nguyên dương: %s\n' "$value_name" "$value" >&2
    exit 64
  fi
done
if [[ ! "$BATCH_INTERVAL_MS" =~ ^[0-9]+$ ]]; then
  printf 'LOAD_BATCH_INTERVAL_MS phải là số nguyên không âm: %s\n' \
    "$BATCH_INTERVAL_MS" >&2
  exit 64
fi
if ((CONCURRENCY > TOTAL_REQUESTS)); then
  printf '%s\n' 'LOAD_CONCURRENCY không được lớn hơn LOAD_TOTAL_REQUESTS.' >&2
  exit 64
fi
if ((BATCH_INTERVAL_MS > 0)) && ! command -v sleep >/dev/null 2>&1; then
  printf '%s\n' 'Thiếu command bắt buộc: sleep' >&2
  exit 69
fi

batch_interval_seconds=$(awk -v milliseconds="$BATCH_INTERVAL_MS" \
  'BEGIN {printf "%.3f", milliseconds / 1000}')
batch_count=$(((TOTAL_REQUESTS + CONCURRENCY - 1) / CONCURRENCY))
minimum_pacing_ms=$(((batch_count - 1) * BATCH_INTERVAL_MS))

read_env_value() {
  local key=$1
  local line value
  line=$(grep -m1 "^${key}=" "$ENV_FILE" || true)
  value=${line#*=}
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value=${value:1:${#value}-2}
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

first_env_value() {
  local key value
  for key in "$@"; do
    value=$(read_env_value "$key")
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
}

if [[ -z "$BASE_URL" ]]; then
  BASE_URL=$(first_env_value SUPABASE_URL SUPABASE_PUBLIC_URL API_EXTERNAL_URL)
fi
PUBLISHABLE_KEY=$(first_env_value \
  SUPABASE_PUBLISHABLE_KEY PUBLISHABLE_KEY ANON_KEY SUPABASE_ANON_KEY)

if [[ -z "$BASE_URL" || -z "$PUBLISHABLE_KEY" ]]; then
  printf '%s\n' \
    'Thiếu SUPABASE_URL/SUPABASE_PUBLIC_URL hoặc SUPABASE_PUBLISHABLE_KEY.' >&2
  exit 78
fi
if [[ "$BASE_URL" != https://* || "$BASE_URL" == *'@'* ]]; then
  printf '%s\n' 'Load gate chỉ nhận HTTPS origin không chứa credential.' >&2
  exit 78
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-load.XXXXXX")
chmod 0700 "$tmp_dir"
cleanup() {
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT

run_request() {
  local index=$1
  curl --connect-timeout 10 --max-time 20 --silent --show-error \
    --output /dev/null \
    --write-out '%{http_code} %{time_total}\n' \
    --header "apikey: $PUBLISHABLE_KEY" \
    "${BASE_URL%/}/auth/v1/health" \
    >"$tmp_dir/$index.result" 2>"$tmp_dir/$index.error"
}

started_at=$(date +%s)
request_index=1
while ((request_index <= TOTAL_REQUESTS)); do
  pids=()
  batch_end=$((request_index + CONCURRENCY - 1))
  if ((batch_end > TOTAL_REQUESTS)); then
    batch_end=$TOTAL_REQUESTS
  fi
  for ((index = request_index; index <= batch_end; index++)); do
    run_request "$index" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done
  request_index=$((batch_end + 1))
  if ((request_index <= TOTAL_REQUESTS && BATCH_INTERVAL_MS > 0)); then
    sleep "$batch_interval_seconds"
  fi
done
elapsed_seconds=$(($(date +%s) - started_at))

success_count=0
failure_count=0
: >"$tmp_dir/times"
for ((index = 1; index <= TOTAL_REQUESTS; index++)); do
  result_file="$tmp_dir/$index.result"
  if [[ ! -s "$result_file" ]]; then
    failure_count=$((failure_count + 1))
    continue
  fi
  read -r status duration <"$result_file"
  if [[ "$status" == 200 ]]; then
    success_count=$((success_count + 1))
    printf '%s\n' "$duration" >>"$tmp_dir/times"
  else
    failure_count=$((failure_count + 1))
  fi
done

if ((success_count == 0)); then
  printf 'Auth load fail: 0/%s request thành công.\n' "$TOTAL_REQUESTS" >&2
  exit 1
fi

sort -n "$tmp_dir/times" >"$tmp_dir/times.sorted"
p95_rank=$(((success_count * 95 + 99) / 100))
p95_seconds=$(awk -v rank="$p95_rank" 'NR == rank {print; exit}' \
  "$tmp_dir/times.sorted")
max_seconds=$(awk 'END {print}' "$tmp_dir/times.sorted")
p95_ms=$(awk -v seconds="$p95_seconds" 'BEGIN {printf "%.0f", seconds * 1000}')
max_ms=$(awk -v seconds="$max_seconds" 'BEGIN {printf "%.0f", seconds * 1000}')

printf '%s\n' \
  "Auth load result: $success_count/$TOTAL_REQUESTS HTTP 200, concurrency $CONCURRENCY, p95 ${p95_ms}ms, max ${max_ms}ms." \
  "Auth load pacing: ${BATCH_INTERVAL_MS}ms giữa $batch_count batch, tối thiểu ${minimum_pacing_ms}ms; elapsed ${elapsed_seconds}s." \
  "Auth load budget: p95 <= ${MAX_P95_MS}ms, max <= ${MAX_SINGLE_MS}ms, failures = 0."

if ((failure_count != 0 ||
  success_count != TOTAL_REQUESTS ||
  p95_ms > MAX_P95_MS ||
  max_ms > MAX_SINGLE_MS)); then
  printf '%s\n' 'Auth load budget fail.' >&2
  exit 1
fi

printf '%s\n' 'Supabase Auth load budget pass.'
