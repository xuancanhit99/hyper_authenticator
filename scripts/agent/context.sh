#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

printf '%s\n' "Repository: $ROOT"
printf '%s\n' "Branch and worktree:"
git status --short --branch

printf '\n%s\n' "Recent commits:"
git log -5 --date=short --pretty=format:'%h %ad %s'
printf '\n'

if command -v flutter >/dev/null 2>&1; then
  printf '\n%s\n' "Flutter:"
  flutter --version | sed -n '1,4p'
else
  printf '\n%s\n' "Flutter: not found"
fi

if command -v dart >/dev/null 2>&1; then
  printf '\n%s\n' "Dart:"
  dart --version 2>&1
else
  printf '\n%s\n' "Dart: not found"
fi

printf '\n%s\n' "Repository inventory:"
printf 'Dart files: '
find lib test tool -type f -name '*.dart' 2>/dev/null | wc -l | tr -d ' '
printf 'Markdown files: '
find . -type f -name '*.md' \
  -not -path './.git/*' \
  -not -path './.claude/*' \
  -not -path './.codex/*' \
  -not -path './.dart_tool/*' \
  -not -path './build/*' \
  -not -path './ios/Pods/*' \
  -not -path './macos/Pods/*' | wc -l | tr -d ' '

printf '\n%s\n' "Known baseline: docs/PROJECT_STATUS.md"
printf '%s\n' "Agent contract: AGENTS.md"
