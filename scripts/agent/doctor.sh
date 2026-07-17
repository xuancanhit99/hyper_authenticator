#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

status=0

ok() {
  printf 'OK   %s\n' "$1"
}

warn() {
  printf 'WARN %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  status=1
}

for command_name in git flutter dart rg; do
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name is available"
  else
    fail "$command_name is required"
  fi
done

for required_file in \
  AGENTS.md \
  docs/README.md \
  docs/PROJECT_STATUS.md \
  docs/SECURITY.md \
  pubspec.yaml \
  .env.example; do
  if [[ -f "$required_file" ]]; then
    ok "$required_file exists"
  else
    fail "$required_file is missing"
  fi
done

if [[ -f .env ]]; then
  ok ".env exists for --dart-define-from-file"
  for key_name in SUPABASE_URL SUPABASE_PUBLISHABLE_KEY; do
    if rg -q "^$key_name=.+$" .env; then
      ok "$key_name is set"
    else
      fail "$key_name is missing or empty"
    fi
  done
else
  warn ".env is absent; analyze/test still work, but running the app requires Supabase defines"
fi

if [[ -n "$(git status --short)" ]]; then
  warn "worktree is dirty; preserve unrelated user changes"
else
  ok "worktree is clean"
fi

exit "$status"
