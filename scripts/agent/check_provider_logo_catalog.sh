#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

SOURCE=third_party/sentinel-icons/SOURCE.json
LICENSE=third_party/sentinel-icons/LICENSE
CHECKSUMS=third_party/sentinel-icons/SHA256SUMS
MAPPING=assets/data/authenticator_logo_map.json
OVERRIDES=assets/data/authenticator_logo_overrides.json
ASSET_DIR=assets/logos/authenticators
UNRESOLVED=third_party/sentinel-icons/UNRESOLVED_MAPPING_VALUES.txt

for path in "$SOURCE" "$LICENSE" "$CHECKSUMS" "$MAPPING" "$OVERRIDES" "$UNRESOLVED"; do
  [[ -f "$path" ]] || {
    printf 'Thiếu provider logo provenance file: %s\n' "$path" >&2
    exit 1
  }
done

expected_count=$(jq -r '.assetCount' "$SOURCE")
actual_count=$(find "$ASSET_DIR" -type f -name '*.png' | wc -l | tr -d ' ')
[[ "$actual_count" == "$expected_count" ]] || {
  printf 'Provider logo count lệch: expected=%s actual=%s\n' \
    "$expected_count" "$actual_count" >&2
  exit 1
}

expected_mapping_sha=$(jq -r '.mappingSha256' "$SOURCE")
actual_mapping_sha=$(shasum -a 256 "$MAPPING" | awk '{print $1}')
[[ "$actual_mapping_sha" == "$expected_mapping_sha" ]] || {
  printf 'Provider logo mapping SHA-256 không khớp source pin.\n' >&2
  exit 1
}

expected_license_sha=$(jq -r '.licenseSha256' "$SOURCE")
actual_license_sha=$(shasum -a 256 "$LICENSE" | awk '{print $1}')
[[ "$actual_license_sha" == "$expected_license_sha" ]] || {
  printf 'Sentinel Icons license SHA-256 không khớp source pin.\n' >&2
  exit 1
}

shasum -a 256 --check "$CHECKSUMS" >/dev/null

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-provider-logos.XXXXXX")
trap 'find "$tmp_dir" -depth -delete' EXIT

find "$ASSET_DIR" -type f -name '*.png' -print0 | xargs -0 file \
  > "$tmp_dir/file-types.txt"
png_payload_count=$(grep -c 'PNG image data' "$tmp_dir/file-types.txt" || true)
jpeg_payload_count=$(grep -c 'JPEG image data' "$tmp_dir/file-types.txt" || true)
unexpected_payload_count=$(grep -Evc 'PNG image data|JPEG image data' \
  "$tmp_dir/file-types.txt" || true)
[[ "$unexpected_payload_count" == 0 ]] || {
  printf 'Provider logo có payload không phải PNG/JPEG:\n' >&2
  grep -Ev 'PNG image data|JPEG image data' "$tmp_dir/file-types.txt" >&2
  exit 1
}
[[ "$png_payload_count" == "$(jq -r '.pngPayloadCount' "$SOURCE")" &&
  "$jpeg_payload_count" == "$(jq -r '.jpegPayloadCountWithPngExtension' "$SOURCE")" ]] || {
  printf 'Provider logo payload inventory lệch source pin.\n' >&2
  exit 1
}

find "$ASSET_DIR" -type f -name '*.png' -exec basename {} .png \; \
  | tr '[:upper:]' '[:lower:]' | LC_ALL=C sort > "$tmp_dir/assets.txt"

duplicates=$(uniq -d "$tmp_dir/assets.txt")
[[ -z "$duplicates" ]] || {
  printf 'Provider logo có tên trùng khi bỏ phân biệt hoa thường:\n%s\n' \
    "$duplicates" >&2
  exit 1
}

jq -r --slurpfile overrides "$OVERRIDES" \
  'to_entries[].value | ($overrides[0][.] // .) | ascii_downcase' "$MAPPING" \
  | LC_ALL=C sort -u > "$tmp_dir/mapped-values.txt"
comm -23 "$tmp_dir/mapped-values.txt" "$tmp_dir/assets.txt" \
  > "$tmp_dir/unresolved.txt"
LC_ALL=C sort "$UNRESOLVED" > "$tmp_dir/expected-unresolved.txt"
cmp -s "$tmp_dir/unresolved.txt" "$tmp_dir/expected-unresolved.txt" || {
  printf 'Danh sách mapping không có asset đã thay đổi:\n' >&2
  diff -u "$tmp_dir/expected-unresolved.txt" "$tmp_dir/unresolved.txt" >&2 || true
  exit 1
}

printf 'Provider logo catalog hợp lệ: %s asset (%s PNG, %s JPEG), %s issuer/alias.\n' \
  "$actual_count" "$png_payload_count" "$jpeg_payload_count" \
  "$(jq 'length' "$MAPPING")"
