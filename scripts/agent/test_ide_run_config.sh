#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONFIG="$ROOT/.run/Hyper Authenticator (local env).run.xml"

fail() {
  printf 'IDE run configuration contract fail: %s\n' "$1" >&2
  exit 1
}

[[ -f "$CONFIG" ]] || fail 'thiếu shared Android Studio run configuration'

grep -Fq 'value="--dart-define-from-file=.env"' "$CONFIG" ||
  fail 'run configuration không inject public client config từ .env'
grep -Fq 'value="$PROJECT_DIR$/lib/main.dart"' "$CONFIG" ||
  fail 'run configuration không trỏ tới lib/main.dart'

if grep -Eq '(\.env\.server|SUPABASE_URL=|SUPABASE_(PUBLISHABLE|ANON)_KEY=|PASSWORD_RECOVERY_URL=|sb_publishable_)' "$CONFIG"; then
  fail 'run configuration chứa server config hoặc giá trị client config'
fi

printf '%s\n' 'IDE run configuration contract pass.'
