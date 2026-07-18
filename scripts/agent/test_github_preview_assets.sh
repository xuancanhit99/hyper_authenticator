#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-preview-test.XXXXXX")
cleanup() {
  find "$WORK_ROOT" -depth -delete
}
trap cleanup EXIT

if command -v sha256sum >/dev/null 2>&1; then
  hash_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  hash_command=(shasum -a 256)
else
  printf '%s\n' 'Thiếu SHA-256 utility (sha256sum hoặc shasum).' >&2
  exit 69
fi

make_fixture() {
  local root=$1
  local version=${2:-1.1.0+10}
  mkdir -p "$root/linux" "$root/windows"
  printf '%s' 'TEST_ONLY_DEBIAN_PACKAGE' \
    > "$root/linux/hyper-authenticator_${version}_amd64.deb"
  printf '%s' 'TEST_ONLY_WINDOWS_INSTALLER' \
    > "$root/windows/hyper-authenticator-${version}-windows-x64-setup.exe"
  (
    cd "$root/linux"
    "${hash_command[@]}" "hyper-authenticator_${version}_amd64.deb" \
      > "hyper-authenticator_${version}_amd64.deb.sha256"
  )
  (
    cd "$root/windows"
    "${hash_command[@]}" \
      "hyper-authenticator-${version}-windows-x64-setup.exe" \
      > "hyper-authenticator-${version}-windows-x64-setup.exe.sha256"
  )
}

expect_failure() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'Expected failure nhưng command đã pass: %s\n' "$label" >&2
    exit 1
  fi
  printf '✓ Fail closed: %s\n' "$label"
}

valid_input="$WORK_ROOT/valid-input"
valid_output="$WORK_ROOT/valid-output"
make_fixture "$valid_input"
mkdir -p "$valid_output"
"$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$valid_input" "$valid_output" >/dev/null
if [[ $(find "$valid_output" -maxdepth 1 -type f | wc -l | tr -d ' ') -ne 5 ]]; then
  printf '%s\n' 'Valid fixture không tạo đúng năm release asset.' >&2
  exit 1
fi
printf '%s\n' '✓ Valid fixture tạo đúng năm release asset'

checksum_input="$WORK_ROOT/checksum-input"
checksum_output="$WORK_ROOT/checksum-output"
make_fixture "$checksum_input"
printf '%s' 'TAMPERED' >> \
  "$checksum_input/linux/hyper-authenticator_1.1.0+10_amd64.deb"
mkdir -p "$checksum_output"
expect_failure checksum \
  "$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$checksum_input" "$checksum_output"

version_input="$WORK_ROOT/version-input"
version_output="$WORK_ROOT/version-output"
make_fixture "$version_input" '1.1.0+9'
mkdir -p "$version_output"
expect_failure version \
  "$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$version_input" "$version_output"

override_output="$WORK_ROOT/version-override-output"
mkdir -p "$override_output"
PACKAGE_VERSION_OVERRIDE='1.1.0+9' \
  "$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$version_input" "$override_output" >/dev/null
printf '%s\n' '✓ Historical package version override pass'

forbidden_input="$WORK_ROOT/forbidden-input"
forbidden_output="$WORK_ROOT/forbidden-output"
make_fixture "$forbidden_input"
printf '%s' 'TEST_ONLY_PUBLIC_CONFIG' > "$forbidden_input/release.env"
mkdir -p "$forbidden_output"
expect_failure forbidden-artifact \
  "$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$forbidden_input" "$forbidden_output"

target_input="$WORK_ROOT/target-input"
target_output="$WORK_ROOT/target-output"
make_fixture "$target_input"
checksum_path="$target_input/linux/hyper-authenticator_1.1.0+10_amd64.deb.sha256"
recorded_hash=$("${hash_command[@]}" \
  "$target_input/linux/hyper-authenticator_1.1.0+10_amd64.deb" | awk '{print $1}')
printf '%s  %s\n' "$recorded_hash" '../outside.deb' > "$checksum_path"
mkdir -p "$target_output"
expect_failure checksum-target \
  "$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$target_input" "$target_output"

nonempty_input="$WORK_ROOT/nonempty-input"
nonempty_output="$WORK_ROOT/nonempty-output"
make_fixture "$nonempty_input"
mkdir -p "$nonempty_output"
printf '%s' 'SENTINEL' > "$nonempty_output/existing.txt"
expect_failure nonempty-output \
  "$ROOT/scripts/agent/check_github_preview_assets.sh" \
  "$nonempty_input" "$nonempty_output"

printf '%s\n' '✓ GitHub Preview asset harness regression pass'
