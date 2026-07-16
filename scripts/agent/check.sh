#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

if [[ $# -gt 0 ]]; then
  MODE=$1
else
  MODE=quick
fi

run_docs() {
  printf '%s\n' "== Documentation gate =="
  dart run tool/agent/check_docs.dart
}

run_quick() {
  local status=0
  run_docs || status=1
  printf '\n%s\n' "== Formatting gate =="
  dart format --output=none --set-exit-if-changed lib test tool || status=1
  printf '\n%s\n' "== Static analysis gate =="
  dart analyze || status=1
  return "$status"
}

run_full() {
  local status=0
  run_quick || status=1
  if [[ ! -f .env ]]; then
    printf '\n%s\n' "ERROR: .env is required because pubspec.yaml bundles it as an asset." >&2
    printf '%s\n' "Create it from .env.example with development Supabase client values." >&2
    status=1
  else
    printf '\n%s\n' "== Flutter test gate =="
    flutter test || status=1
  fi
  return "$status"
}

case "$MODE" in
  docs)
    run_docs
    ;;
  quick)
    run_quick
    ;;
  full)
    run_full
    ;;
  *)
    printf 'Usage: %s [docs|quick|full]\n' "$0" >&2
    exit 64
    ;;
esac
