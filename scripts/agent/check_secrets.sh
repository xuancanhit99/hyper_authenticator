#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

if ! command -v gitleaks >/dev/null 2>&1; then
  printf '%s\n' \
    'Thiếu gitleaks. Cài bản được pin trong .github/workflows/ci.yml rồi chạy lại.' >&2
  exit 69
fi

gitleaks git . --redact --no-banner

if ! git diff --cached --quiet; then
  gitleaks git . --staged --redact --no-banner
fi

printf '%s\n' 'Secret gate pass: lịch sử commit và staged changes không có leak.'
