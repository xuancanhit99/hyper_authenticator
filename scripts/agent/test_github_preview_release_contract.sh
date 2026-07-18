#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VERIFIER="$ROOT/scripts/agent/verify_github_preview_release.sh"
PUBLISHER="$ROOT/scripts/agent/github_preview_release.sh"

bash -n "$VERIFIER" "$PUBLISHER"

expect_failure() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'Expected failure nhưng command đã pass: %s\n' "$label" >&2
    exit 1
  fi
  printf '✓ Fail closed: %s\n' "$label"
}

expect_failure invalid-tag \
  "$VERIFIER" v1.1.0 xuancanhit99/hyper_authenticator
expect_failure invalid-repository \
  "$VERIFIER" v1.1.0-preview.1 'invalid repository'
expect_failure invalid-expected-commit \
  "$VERIFIER" v1.1.0-preview.1 xuancanhit99/hyper_authenticator not-a-commit

search_regex() {
  local pattern=$1
  local path=$2
  if command -v rg >/dev/null 2>&1; then
    rg -n -- "$pattern" "$path"
  else
    grep -En -- "$pattern" "$path"
  fi
}

search_fixed() {
  local pattern=$1
  local path=$2
  if command -v rg >/dev/null 2>&1; then
    rg -F -- "$pattern" "$path"
  else
    grep -F -- "$pattern" "$path"
  fi
}

if search_regex '(--header|-H)[[:space:]]+.*Authorization' "$VERIFIER" \
  >/dev/null; then
  printf '%s\n' \
    'Public verifier không được cấu hình Authorization header.' >&2
  exit 1
fi
if ! search_fixed 'gh release edit "$TAG" --repo "$repo" --draft' \
  "$PUBLISHER" >/dev/null; then
  printf '%s\n' 'Publisher thiếu fail-closed draft rollback.' >&2
  exit 1
fi

printf '%s\n' '✓ Public release contract harness pass'
