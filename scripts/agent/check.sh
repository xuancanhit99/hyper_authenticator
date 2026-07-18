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

run_generated() {
  printf '\n%s\n' "== Generated-code drift gate =="

  local status=0
  local output_dir
  output_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-generated.XXXXXX")
  local generated_file="$output_dir/packages/hyper_authenticator/injection_container.config.dart"

  if ! dart run build_runner build \
    --output "$output_dir" \
    --build-filter lib/injection_container.config.dart; then
    status=1
  elif [[ ! -f "$generated_file" ]]; then
    printf '%s\n' "Generated output không tồn tại: $generated_file" >&2
    status=1
  elif ! cmp -s lib/injection_container.config.dart "$generated_file"; then
    printf '%s\n' \
      "lib/injection_container.config.dart không khớp annotation hiện tại." >&2
    printf '%s\n' "Chạy: dart run build_runner build" >&2
    status=1
  else
    printf '%s\n' "Generated code khớp source annotation."
  fi

  find "$output_dir" -depth -delete
  return "$status"
}

run_platform() {
  printf '\n%s\n' "== Platform configuration gate =="
  dart run tool/agent/check_platform_config.dart
}

run_release_harness() {
  printf '\n%s\n' "== GitHub Preview release harness gate =="
  scripts/agent/test_github_preview_assets.sh
  scripts/agent/test_github_preview_release_contract.sh
}

run_quick() {
  local status=0
  run_docs || status=1
  run_generated || status=1
  printf '\n%s\n' "== Formatting gate =="
  dart format --output=none --set-exit-if-changed \
    lib test integration_test tool || status=1
  printf '\n%s\n' "== Static analysis gate =="
  dart analyze || status=1
  return "$status"
}

run_full() {
  local status=0
  run_quick || status=1
  run_platform || status=1
  run_release_harness || status=1
  printf '\n%s\n' "== Flutter test gate =="
  flutter test || status=1
  printf '\n%s\n' "== Supabase encrypted migration gate =="
  scripts/supabase/test_encrypted_vault_migration.sh || status=1
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
