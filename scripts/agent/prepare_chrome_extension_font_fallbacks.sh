#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DESTINATION=${1:-"$ROOT/.dart_tool/chrome_extension_font_fallbacks"}
LOCK_FILE=${2:-"$ROOT/chrome_extension/font-fallbacks/sources.lock"}
EXPECTED_ENTRIES=868
EXPECTED_FONTS=724
EXPECTED_LICENSES=144
DOWNLOAD_JOBS=${HYPER_FONT_DOWNLOAD_JOBS:-12}
GOOGLE_FONTS_COMMIT=038b637da7b3fd956a4ed93ffc607c3d5e4ce172

usage() {
  printf '%s\n' \
    'Usage: prepare_chrome_extension_font_fallbacks.sh [destination] [sources.lock]' >&2
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

validate_entry() {
  local expected_sha=$1
  local source_url=$2
  local relative_path=$3
  local expected_url
  local family

  if [[ ! "$expected_sha" =~ ^[0-9a-f]{64}$ ]] ||
    [[ "$relative_path" == /* ]] ||
    [[ "$relative_path" == *'..'* ]] ||
    [[ ! "$relative_path" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    printf 'Entry font fallback không hợp lệ: %s\n' "$relative_path" >&2
    return 65
  fi

  if [[ "$relative_path" == *.woff2 ]]; then
    expected_url="https://fonts.gstatic.com/s/$relative_path"
  elif [[ "$relative_path" =~ ^licenses/([a-z0-9]+)/OFL\.txt$ ]]; then
    family=${BASH_REMATCH[1]}
    expected_url="https://raw.githubusercontent.com/google/fonts/$GOOGLE_FONTS_COMMIT/ofl/$family/OFL.txt"
  else
    printf 'Loại file font fallback không được hỗ trợ: %s\n' "$relative_path" >&2
    return 65
  fi

  if [[ "$source_url" != "$expected_url" ]]; then
    printf 'Nguồn font fallback không khớp path/pin: %s\n' "$relative_path" >&2
    return 65
  fi
}

if [[ ${1:-} == '--download-one' ]]; then
  if [[ $# -ne 5 ]]; then
    usage
    exit 64
  fi
  destination=$2
  expected_sha=$3
  source_url=$4
  relative_path=$5
  validate_entry "$expected_sha" "$source_url" "$relative_path"
  target="$destination/$relative_path"
  if [[ -L "$destination" ]] || [[ -L "$target" ]]; then
    printf 'Font fallback cache không chấp nhận symlink: %s\n' "$relative_path" >&2
    exit 65
  fi
  mkdir -p "$(dirname "$target")"
  temporary_file=$(mktemp "${target}.download.XXXXXX")
  if ! curl --fail --silent --show-error --location --retry 3 \
    --connect-timeout 15 --max-time 120 \
    "$source_url" --output "$temporary_file"; then
    rm -f "$temporary_file"
    printf 'Không tải được font fallback đã pin: %s\n' "$relative_path" >&2
    exit 69
  fi
  if [[ $(sha256_file "$temporary_file") != "$expected_sha" ]]; then
    rm -f "$temporary_file"
    printf 'Checksum font fallback không khớp: %s\n' "$relative_path" >&2
    exit 65
  fi
  mv "$temporary_file" "$target"
  exit 0
fi

if [[ $# -gt 2 ]]; then
  usage
  exit 64
fi
if [[ ! "$DOWNLOAD_JOBS" =~ ^[0-9]+$ ]] ||
  ((DOWNLOAD_JOBS < 1 || DOWNLOAD_JOBS > 32)); then
  printf '%s\n' 'HYPER_FONT_DOWNLOAD_JOBS phải nằm trong khoảng 1..32.' >&2
  exit 64
fi
if [[ ! -f "$LOCK_FILE" ]] || [[ -L "$LOCK_FILE" ]]; then
  printf 'Font fallback lock không hợp lệ: %s\n' "$LOCK_FILE" >&2
  exit 65
fi

entry_count=$(awk -F '\t' 'NF { count++ } END { print count + 0 }' "$LOCK_FILE")
if [[ "$entry_count" != "$EXPECTED_ENTRIES" ]]; then
  printf 'Font fallback lock phải có đúng %s entry, hiện có %s.\n' \
    "$EXPECTED_ENTRIES" "$entry_count" >&2
  exit 65
fi
if awk -F '\t' 'NF != 3 { invalid=1 } END { exit invalid ? 0 : 1 }' "$LOCK_FILE"; then
  printf '%s\n' 'Font fallback lock phải dùng đúng ba cột TSV.' >&2
  exit 65
fi
if [[ -n $(cut -f3 "$LOCK_FILE" | LC_ALL=C sort | uniq -d) ]]; then
  printf '%s\n' 'Font fallback lock chứa path trùng.' >&2
  exit 65
fi

font_count=$(awk -F '\t' '$3 ~ /\.woff2$/ { count++ } END { print count + 0 }' "$LOCK_FILE")
license_count=$(awk -F '\t' '$3 ~ /^licenses\/[a-z0-9]+\/OFL\.txt$/ { count++ } END { print count + 0 }' "$LOCK_FILE")
if [[ "$font_count" != "$EXPECTED_FONTS" ]] ||
  [[ "$license_count" != "$EXPECTED_LICENSES" ]]; then
  printf 'Font fallback lock sai inventory: fonts=%s, licenses=%s.\n' \
    "$font_count" "$license_count" >&2
  exit 65
fi

if [[ -L "$DESTINATION" ]]; then
  printf 'Font fallback cache không chấp nhận symlink: %s\n' "$DESTINATION" >&2
  exit 65
fi
mkdir -p "$DESTINATION"
if find "$DESTINATION" -type l -print -quit | grep -q .; then
  printf 'Font fallback cache chứa symlink: %s\n' "$DESTINATION" >&2
  exit 65
fi
expected_paths=$(mktemp "${TMPDIR:-/tmp}/hyper-font-fallback-paths.XXXXXX")
download_queue=$(mktemp "${TMPDIR:-/tmp}/hyper-font-fallback-downloads.XXXXXX")
trap 'rm -f "$expected_paths" "$download_queue"' EXIT
cut -f3 "$LOCK_FILE" | LC_ALL=C sort >"$expected_paths"

while IFS=$'\t' read -r expected_sha source_url relative_path; do
  validate_entry "$expected_sha" "$source_url" "$relative_path"

  target="$DESTINATION/$relative_path"
  if [[ -s "$target" ]] && [[ $(sha256_file "$target") == "$expected_sha" ]]; then
    continue
  fi
  printf '%s\0%s\0%s\0' "$expected_sha" "$source_url" "$relative_path" \
    >>"$download_queue"
done <"$LOCK_FILE"

if [[ -s "$download_queue" ]]; then
  xargs -0 -n 3 -P "$DOWNLOAD_JOBS" \
    "$0" --download-one "$DESTINATION" <"$download_queue"
fi

while IFS= read -r -d '' cached_file; do
  relative_path=${cached_file#"$DESTINATION"/}
  if ! grep -Fxq "$relative_path" "$expected_paths"; then
    rm -f "$cached_file"
  fi
done < <(find "$DESTINATION" -type f -print0)
find "$DESTINATION" -depth -type d -empty -delete

actual_count=$(find "$DESTINATION" -type f | wc -l | tr -d ' ')
if [[ "$actual_count" != "$EXPECTED_ENTRIES" ]]; then
  printf 'Font fallback cache không đầy đủ: %s/%s file.\n' \
    "$actual_count" "$EXPECTED_ENTRIES" >&2
  exit 65
fi

printf 'Font fallback cache pass: %s font, %s license tại %s\n' \
  "$EXPECTED_FONTS" "$EXPECTED_LICENSES" "$DESTINATION"
