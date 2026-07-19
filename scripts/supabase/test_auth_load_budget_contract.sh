#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-load-contract.XXXXXX")
cleanup() {
  find "$SANDBOX" -depth -delete
}
trap cleanup EXIT

mkdir -p "$SANDBOX/bin"
chmod 0700 "$SANDBOX" "$SANDBOX/bin"
umask 077

cat >"$SANDBOX/env" <<'EOF'
SUPABASE_URL=https://supabase.example.invalid
SUPABASE_PUBLISHABLE_KEY=TEST_ONLY_PUBLIC_KEY
EOF

cat >"$SANDBOX/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '200 0.050000'
EOF

cat >"$SANDBOX/bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$LOAD_CONTRACT_SLEEP_LOG"
EOF
chmod 0700 "$SANDBOX/bin/curl" "$SANDBOX/bin/sleep"

export LOAD_CONTRACT_SLEEP_LOG="$SANDBOX/sleep.log"
output=$(PATH="$SANDBOX/bin:$PATH" \
  LOAD_TOTAL_REQUESTS=5 \
  LOAD_CONCURRENCY=2 \
  LOAD_BATCH_INTERVAL_MS=250 \
  "$ROOT/scripts/supabase/test_auth_load_budget.sh" "$SANDBOX/env")

grep -Fq \
  'Auth load result: 5/5 HTTP 200, concurrency 2, p95 50ms, max 50ms.' \
  <<<"$output"
grep -Fq \
  'Auth load pacing: 250ms giữa 3 batch, tối thiểu 500ms;' \
  <<<"$output"
if [[ $(wc -l <"$LOAD_CONTRACT_SLEEP_LOG" | tr -d ' ') != 2 ]]; then
  printf '%s\n' 'Pacing phải sleep đúng giữa ba batch.' >&2
  exit 1
fi
if grep -Fvxq '0.250' "$LOAD_CONTRACT_SLEEP_LOG"; then
  printf '%s\n' 'Pacing sleep không dùng đúng khoảng 0.250 giây.' >&2
  exit 1
fi

if PATH="$SANDBOX/bin:$PATH" \
  LOAD_BATCH_INTERVAL_MS=-1 \
  "$ROOT/scripts/supabase/test_auth_load_budget.sh" "$SANDBOX/env" \
  >"$SANDBOX/invalid.out" 2>"$SANDBOX/invalid.err"; then
  printf '%s\n' 'Load gate phải từ chối pacing âm.' >&2
  exit 1
fi
grep -Fq 'LOAD_BATCH_INTERVAL_MS phải là số nguyên không âm' \
  "$SANDBOX/invalid.err"

printf '%s\n' \
  'Auth load pacing contract pass: paced batches và invalid input fail closed.'
