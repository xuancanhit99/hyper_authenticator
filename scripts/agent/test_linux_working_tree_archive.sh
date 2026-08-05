#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/scripts/agent/list_working_tree_source_files.sh"
SANDBOX=$(mktemp -d \
  "${TMPDIR:-/tmp}/hyper-auth-linux-archive-contract.XXXXXX")
cleanup() {
  find "$SANDBOX" -depth -delete
}
trap cleanup EXIT

fixture="$SANDBOX/repository"
mkdir "$fixture"
cd "$fixture"
git init --quiet
printf '%s\n' 'tracked' >'tracked file.txt'
printf '%s\n' 'delete-before-archive' >deleted.txt
printf '%s\n' '*.env' >.gitignore
ln -s missing-target tracked-broken-link
git add .gitignore 'tracked file.txt' deleted.txt tracked-broken-link
git -c user.name='TEST_ONLY Agent' \
  -c user.email='test-only@example.invalid' \
  commit --quiet -m 'test fixture'

rm deleted.txt
printf '%s\n' 'untracked' >'untracked file.txt'
printf '%s\n' 'must-not-leak' >secret.env

archive="$SANDBOX/source.tar"
bash "$HELPER" |
  COPYFILE_DISABLE=1 tar --no-xattrs --null --files-from=- -cf "$archive"
listing=$(tar -tf "$archive")

for expected in \
  '.gitignore' \
  'tracked file.txt' \
  'tracked-broken-link' \
  'untracked file.txt'; do
  if ! grep -Fqx "$expected" <<<"$listing"; then
    printf 'Archive thiếu source path hợp lệ: %s\n' "$expected" >&2
    exit 1
  fi
done

for forbidden in deleted.txt secret.env .git; do
  if grep -Fqx "$forbidden" <<<"$listing"; then
    printf 'Archive chứa path phải bị loại: %s\n' "$forbidden" >&2
    exit 1
  fi
done

printf '%s\n' \
  'Linux working-tree archive contract pass: deletion, untracked, ignored và symlink.'
