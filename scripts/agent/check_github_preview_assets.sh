#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ARTIFACT_ROOT=${1:-}
OUTPUT_DIR=${2:-}

if [[ -z "$ARTIFACT_ROOT" || -z "$OUTPUT_DIR" ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/check_github_preview_assets.sh ARTIFACT_ROOT OUTPUT_DIR' >&2
  exit 64
fi

if [[ ! -d "$ARTIFACT_ROOT" ]]; then
  printf 'Artifact root không tồn tại: %s\n' "$ARTIFACT_ROOT" >&2
  exit 66
fi

package_version=$(
  awk '$1 == "version:" { print $2; exit }' "$ROOT/pubspec.yaml"
)
if [[ -z "$package_version" ]]; then
  printf '%s\n' 'Không đọc được version từ pubspec.yaml.' >&2
  exit 65
fi

find_sorted() {
  find "$ARTIFACT_ROOT" -type f "$@" -print | LC_ALL=C sort
}

deb_files=()
while IFS= read -r value; do deb_files+=("$value"); done \
  < <(find_sorted -name 'hyper-authenticator_*.deb')
deb_checksums=()
while IFS= read -r value; do deb_checksums+=("$value"); done \
  < <(find_sorted -name 'hyper-authenticator_*.deb.sha256')
exe_files=()
while IFS= read -r value; do exe_files+=("$value"); done \
  < <(find_sorted -name 'hyper-authenticator-*-windows-x64-setup.exe')
exe_checksums=()
while IFS= read -r value; do exe_checksums+=("$value"); done \
  < <(find_sorted -name 'hyper-authenticator-*-windows-x64-setup.exe.sha256')

if [[ ${#deb_files[@]} -ne 1 || ${#deb_checksums[@]} -ne 1 ]]; then
  printf '%s\n' 'Release bundle phải có đúng một Debian package và checksum.' >&2
  exit 1
fi
if [[ ${#exe_files[@]} -ne 1 || ${#exe_checksums[@]} -ne 1 ]]; then
  printf '%s\n' 'Release bundle phải có đúng một Windows installer và checksum.' >&2
  exit 1
fi

expected_deb="hyper-authenticator_${package_version}_amd64.deb"
expected_exe="hyper-authenticator-${package_version}-windows-x64-setup.exe"
if [[ $(basename "${deb_files[0]}") != "$expected_deb" ]]; then
  printf 'Debian package không khớp pubspec version %s: %s\n' \
    "$package_version" "$(basename "${deb_files[0]}")" >&2
  exit 1
fi
if [[ $(basename "${exe_files[0]}") != "$expected_exe" ]]; then
  printf 'Windows installer không khớp pubspec version %s: %s\n' \
    "$package_version" "$(basename "${exe_files[0]}")" >&2
  exit 1
fi

if [[ $(dirname "${deb_files[0]}") != $(dirname "${deb_checksums[0]}") ]] ||
  [[ $(dirname "${exe_files[0]}") != $(dirname "${exe_checksums[0]}") ]]; then
  printf '%s\n' 'Binary và checksum phải nằm cùng artifact directory.' >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  hash_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  hash_command=(shasum -a 256)
else
  printf '%s\n' 'Thiếu SHA-256 utility (sha256sum hoặc shasum).' >&2
  exit 69
fi

checksum_binaries=("${deb_files[0]}" "${exe_files[0]}")
checksum_files=("${deb_checksums[0]}" "${exe_checksums[0]}")
for index in 0 1; do
  checksum=${checksum_files[$index]}
  binary=${checksum_binaries[$index]}
  checksum_dir=$(dirname "$checksum")
  checksum_name=$(basename "$checksum")
  if [[ $(wc -l < "$checksum" | tr -d ' ') -ne 1 ]]; then
    printf 'Checksum phải có đúng một dòng: %s\n' "$checksum_name" >&2
    exit 1
  fi
  read -r recorded_hash recorded_file < "$checksum"
  if [[ ! "$recorded_hash" =~ ^[0-9a-fA-F]{64}$ ]] ||
    [[ "$recorded_file" != $(basename "$binary") ]]; then
    printf 'Checksum target không khớp binary allowlist: %s\n' \
      "$checksum_name" >&2
    exit 1
  fi
  (
    cd "$checksum_dir"
    "${hash_command[@]}" --check "$checksum_name"
  )
done

if find "$ARTIFACT_ROOT" -type f \( \
  -name '.env' -o -name '*.env' -o -name '*.map' -o -name '*.debug' \
  -o -name '*.pdb' -o -name '*.ilk' -o -name '*.lib' -o -name '*.exp' \
\) -print -quit | grep -q .; then
  printf '%s\n' \
    'Từ chối release bundle chứa env/source-map/debug artifact.' >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
if find "$OUTPUT_DIR" -mindepth 1 -print -quit | grep -q .; then
  printf 'Output directory phải rỗng: %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi
for source in \
  "${deb_files[0]}" "${deb_checksums[0]}" \
  "${exe_files[0]}" "${exe_checksums[0]}"; do
  cp "$source" "$OUTPUT_DIR/$(basename "$source")"
done

(
  cd "$OUTPUT_DIR"
  "${hash_command[@]}" \
    "$(basename "${deb_files[0]}")" \
    "$(basename "${exe_files[0]}")" \
    > SHA256SUMS.txt
  "${hash_command[@]}" --check SHA256SUMS.txt
)

printf '%s\n' "✓ GitHub Preview assets hợp lệ cho version $package_version"
printf '%s\n' "✓ Staging directory: $OUTPUT_DIR"
