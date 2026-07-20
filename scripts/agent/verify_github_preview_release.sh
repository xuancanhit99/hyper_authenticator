#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TAG=${1:-}
REPOSITORY=${2:-xuancanhit99/hyper_authenticator}
EXPECTED_COMMIT=${3:-}
API_ROOT=https://api.github.com

usage() {
  printf '%s\n' \
    'Usage: scripts/agent/verify_github_preview_release.sh TAG [OWNER/REPO] [EXPECTED_COMMIT]' >&2
}

if [[ -z "$TAG" ]]; then
  usage
  exit 64
fi
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$ ]]; then
  printf 'Tag GitHub Preview không hợp lệ: %s\n' "$TAG" >&2
  exit 64
fi
if [[ ! "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf 'GitHub repository không hợp lệ: %s\n' "$REPOSITORY" >&2
  exit 64
fi
if [[ -n "$EXPECTED_COMMIT" ]] &&
  [[ ! "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'Expected commit không hợp lệ: %s\n' "$EXPECTED_COMMIT" >&2
  exit 64
fi

for command in curl jq file cmp grep; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu public release verification dependency: %s\n' "$command" >&2
    exit 69
  fi
done
if command -v sha256sum >/dev/null 2>&1; then
  hash_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  hash_command=(shasum -a 256)
else
  printf '%s\n' 'Thiếu SHA-256 utility (sha256sum hoặc shasum).' >&2
  exit 69
fi

case "$TAG" in
  v1.1.0-preview.1|v1.1.0-preview.2|v1.1.0-preview.3)
    require_android_signed_apk=false
    ;;
  *)
    require_android_signed_apk=true
    ;;
esac
expected_android_fingerprint=$(tr -d ':[:space:]' \
  < "$ROOT/android/app-signing-certificate.sha256" | tr '[:upper:]' '[:lower:]')
if [[ ! "$expected_android_fingerprint" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' 'Fingerprint pin Android không hợp lệ.' >&2
  exit 65
fi

cd "$ROOT"

api_get() {
  local path=$1
  curl --disable --proto '=https' --tlsv1.2 \
    --fail --location --silent --show-error \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    "$API_ROOT/$path"
}

# Cố ý không gửi Authorization: gate phải chứng minh repository/release/assets
# thực sự public và tải được như một người dùng chưa đăng nhập.
release_json=$(api_get "repos/$REPOSITORY/releases/tags/$TAG")
if ! jq -e --arg tag "$TAG" '
  .tag_name == $tag and
  .draft == false and
  .prerelease == true and
  (.published_at | type == "string") and
  (.html_url | type == "string")
' >/dev/null <<<"$release_json"; then
  printf '%s\n' 'Release không phải public non-draft pre-release đúng tag.' >&2
  exit 1
fi
package_version=$(jq -r '
  try (
    .body |
    capture("Package version: `(?<version>[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+)`") |
    .version
  ) catch ""
' <<<"$release_json")
app_version=${package_version%%+*}
if [[ -z "$package_version" || "$TAG" != "v${app_version}-preview."* ]]; then
  printf 'Release package version không khớp tag %s: %s.\n' \
    "$TAG" "$package_version" >&2
  exit 1
fi

ref_json=$(api_get "repos/$REPOSITORY/git/ref/tags/$TAG")
object_type=$(jq -r '.object.type // empty' <<<"$ref_json")
object_sha=$(jq -r '.object.sha // empty' <<<"$ref_json")
case "$object_type" in
  commit)
    tag_commit=$object_sha
    ;;
  tag)
    tag_json=$(api_get "repos/$REPOSITORY/git/tags/$object_sha")
    if [[ $(jq -r '.object.type // empty' <<<"$tag_json") != commit ]]; then
      printf '%s\n' 'Annotated tag không trỏ trực tiếp tới commit.' >&2
      exit 1
    fi
    tag_commit=$(jq -r '.object.sha // empty' <<<"$tag_json")
    ;;
  *)
    printf 'Git tag object type không hợp lệ: %s\n' "$object_type" >&2
    exit 1
    ;;
esac
if [[ ! "$tag_commit" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'Không đọc được tag commit hợp lệ: %s\n' "$tag_commit" >&2
  exit 1
fi
if [[ -n "$EXPECTED_COMMIT" && "$tag_commit" != "$EXPECTED_COMMIT" ]]; then
  printf 'Tag commit mismatch: expected %s, actual %s.\n' \
    "$EXPECTED_COMMIT" "$tag_commit" >&2
  exit 1
fi
if ! jq -e --arg tag "$TAG" --arg commit "$tag_commit" '
  (.body | contains("Source tag: `" + $tag + "`")) and
  (.body | contains("Commit: `" + $commit + "`"))
' >/dev/null <<<"$release_json"; then
  printf '%s\n' 'Release note thiếu exact source tag hoặc commit provenance.' >&2
  exit 1
fi

run_json=$(api_get \
  "repos/$REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$tag_commit&event=push&status=success&per_page=100")
run_id=$(jq -r --arg tag "$TAG" --arg commit "$tag_commit" '
  [.workflow_runs[] |
    select(
      .head_branch == $tag and
      .head_sha == $commit and
      .status == "completed" and
      .conclusion == "success"
    )
  ] | sort_by(.created_at) | last | .id // empty
' <<<"$run_json")
if [[ -z "$run_id" ]]; then
  printf '%s\n' 'Không tìm thấy successful public CI run cho exact tag/commit.' >&2
  exit 1
fi
if ! jq -e --arg run "/actions/runs/$run_id" \
  '.body | contains($run)' >/dev/null <<<"$release_json"; then
  printf '%s\n' 'Release note không trỏ tới exact successful tag CI run.' >&2
  exit 1
fi

expected_names=$(printf '%s\n' \
  'SHA256SUMS.txt' \
  "hyper-authenticator-${package_version}-windows-x64-setup.exe" \
  "hyper-authenticator-${package_version}-windows-x64-setup.exe.sha256" \
  "hyper-authenticator_${package_version}_amd64.deb" \
  "hyper-authenticator_${package_version}_amd64.deb.sha256" | LC_ALL=C sort)
if [[ "$require_android_signed_apk" == true ]]; then
  expected_names=$(printf '%s\n%s\n%s\n' \
    "$expected_names" \
    "hyper-authenticator-${package_version}-android.apk" \
    "hyper-authenticator-${package_version}-android.apk.sha256" | LC_ALL=C sort)
  if ! jq -e --arg fingerprint "$expected_android_fingerprint" \
    '.body | contains("Android app-signing certificate SHA-256: `" + $fingerprint + "`")' \
    >/dev/null <<<"$release_json"; then
    printf '%s\n' 'Release note thiếu exact Android signing fingerprint.' >&2
    exit 1
  fi
fi
actual_names=$(jq -r '.assets[].name' <<<"$release_json" | LC_ALL=C sort)
if [[ "$actual_names" != "$expected_names" ]]; then
  printf '%s\n' 'Public release asset allowlist không khớp.' >&2
  diff -u <(printf '%s\n' "$expected_names") \
    <(printf '%s\n' "$actual_names") >&2 || true
  exit 1
fi
if ! jq -e --arg prefix \
  "https://github.com/$REPOSITORY/releases/download/$TAG/" '
  all(.assets[];
    .state == "uploaded" and
    .size > 0 and
    (.digest | test("^sha256:[0-9a-f]{64}$")) and
    (.browser_download_url | startswith($prefix))
  )
' >/dev/null <<<"$release_json"; then
  printf '%s\n' 'Asset state/size/digest/download URL không đạt public contract.' >&2
  exit 1
fi

work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-public.XXXXXX")
cleanup() {
  find "$work_dir" -depth -delete
}
trap cleanup EXIT
download_dir="$work_dir/download"
staging_dir="$work_dir/staging"
mkdir -p "$download_dir" "$staging_dir"

while IFS=$'\t' read -r name url api_digest; do
  destination="$download_dir/$name"
  curl --disable --proto '=https' --tlsv1.2 \
    --fail --location --silent --show-error \
    --retry 3 --retry-delay 2 --retry-all-errors \
    "$url" --output "$destination"
  actual_digest=$("${hash_command[@]}" "$destination" | awk '{print $1}')
  if [[ "$actual_digest" != "${api_digest#sha256:}" ]]; then
    printf 'Public asset digest mismatch: %s\n' "$name" >&2
    exit 1
  fi
done < <(jq -r '.assets[] | [.name, .browser_download_url, .digest] | @tsv' \
  <<<"$release_json")

PACKAGE_VERSION_OVERRIDE="$package_version" \
REQUIRE_ANDROID_SIGNED_APK="$require_android_signed_apk" \
  scripts/agent/check_github_preview_assets.sh \
  "$download_dir" "$staging_dir" >/dev/null
if ! cmp -s "$download_dir/SHA256SUMS.txt" "$staging_dir/SHA256SUMS.txt"; then
  printf '%s\n' 'Public SHA256SUMS.txt không khớp manifest tái tạo từ binary.' >&2
  exit 1
fi

deb_path="$download_dir/hyper-authenticator_${package_version}_amd64.deb"
exe_path="$download_dir/hyper-authenticator-${package_version}-windows-x64-setup.exe"
deb_description=$(file -b "$deb_path")
exe_description=$(file -b "$exe_path")
if [[ "$deb_description" != *'Debian binary package'* ]]; then
  printf 'Public Linux asset không phải Debian package: %s\n' \
    "$deb_description" >&2
  exit 1
fi
if [[ "$exe_description" != *'PE32 executable'* ]]; then
  printf 'Public Windows asset không phải PE32 executable: %s\n' \
    "$exe_description" >&2
  exit 1
fi

if [[ "$require_android_signed_apk" == true ]]; then
  apk_path="$download_dir/hyper-authenticator-${package_version}-android.apk"
  apksigner=${ANDROID_APKSIGNER:-}
  if [[ -z "$apksigner" ]]; then
    sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
    if [[ -z "$sdk_root" && -f "$ROOT/android/local.properties" ]]; then
      sdk_root=$(awk -F= '$1 == "sdk.dir" {
        value = substr($0, index($0, "=") + 1)
        print value
        exit
      }' "$ROOT/android/local.properties")
    fi
    if [[ -z "$sdk_root" && -d "$HOME/Library/Android/sdk" ]]; then
      sdk_root="$HOME/Library/Android/sdk"
    fi
    if [[ -n "$sdk_root" && -d "$sdk_root/build-tools" ]]; then
      apksigner=$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 \
        -type f -name apksigner -perm -u+x -print | LC_ALL=C sort | tail -n 1)
    fi
  fi
  if [[ -z "$apksigner" || ! -x "$apksigner" ]]; then
    printf '%s\n' 'Không tìm thấy apksigner để xác minh public Android APK.' >&2
    exit 69
  fi
  apk_verification=$($apksigner verify --verbose --print-certs "$apk_path") || {
    printf '%s\n' 'Public Android APK signature verification thất bại.' >&2
    exit 1
  }
  if ! grep -Fxq 'Number of signers: 1' <<<"$apk_verification"; then
    printf '%s\n' 'Public Android APK phải có đúng một signer.' >&2
    exit 1
  fi
  actual_android_fingerprint=$(awk -F': ' \
    '/certificate SHA-256 digest:/{print $NF; exit}' \
    <<<"$apk_verification" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
  unset apk_verification
  if [[ "$actual_android_fingerprint" != "$expected_android_fingerprint" ]]; then
    printf '%s\n' 'Public Android APK signer fingerprint mismatch.' >&2
    exit 1
  fi
fi

release_url=$(jq -r .html_url <<<"$release_json")
printf '%s\n' "✓ Public GitHub Preview: $release_url"
printf '%s\n' "✓ Tag commit: $tag_commit"
printf '%s\n' "✓ Successful tag CI run: $run_id"
if [[ "$require_android_signed_apk" == true ]]; then
  printf '%s\n' '✓ Exact 7 assets, GitHub digest, checksum và manifest đều khớp'
  printf '%s\n' '✓ Android signer, Linux Debian và Windows PE32 đều hợp lệ'
else
  printf '%s\n' '✓ Legacy exact 5 assets, GitHub digest, checksum và manifest đều khớp'
  printf '%s\n' '✓ Linux Debian và Windows PE32 file signatures hợp lệ'
fi
