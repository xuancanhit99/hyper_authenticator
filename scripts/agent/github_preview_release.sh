#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TAG=${1:-}
CONFIRMATION=${2:-}
CHROME_EXTENSION_RUNTIME_ACCEPTANCE=${3:-}
EXPECTED_CONFIRMATION=PUBLISH_UNSIGNED_GITHUB_PREVIEW
EXPECTED_CHROME_EXTENSION_RUNTIME_ACCEPTANCE=OWNER_WAIVED_CHROME_EXTENSION_RUNTIME_ACCEPTANCE

usage() {
  printf '%s\n' \
    'Usage: scripts/agent/github_preview_release.sh vX.Y.Z-preview.N CONFIRMATION CHROME_EXTENSION_RUNTIME_ACCEPTANCE' \
    "Confirmation bắt buộc: $EXPECTED_CONFIRMATION" \
    "Chrome Extension acknowledgement bắt buộc: $EXPECTED_CHROME_EXTENSION_RUNTIME_ACCEPTANCE" >&2
}

if [[ -z "$TAG" || -z "$CONFIRMATION" ||
  -z "$CHROME_EXTENSION_RUNTIME_ACCEPTANCE" ]]; then
  usage
  exit 64
fi
if [[ "$CHROME_EXTENSION_RUNTIME_ACCEPTANCE" != \
  "$EXPECTED_CHROME_EXTENSION_RUNTIME_ACCEPTANCE" ]]; then
  printf '%s\n' 'Từ chối publish: Chrome Extension runtime acknowledgement không khớp.' >&2
  exit 64
fi
if [[ "$CONFIRMATION" != "$EXPECTED_CONFIRMATION" ]]; then
  printf '%s\n' 'Từ chối publish: confirmation không khớp.' >&2
  exit 64
fi
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$ ]]; then
  printf 'Tag GitHub Preview không hợp lệ: %s\n' "$TAG" >&2
  exit 64
fi

for command in git gh jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu release dependency: %s\n' "$command" >&2
    exit 69
  fi
done

cd "$ROOT"
package_version=$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)
app_version=${package_version%%+*}
if [[ "$TAG" != "v${app_version}-preview."* ]]; then
  printf 'Tag %s không khớp app version %s.\n' "$TAG" "$package_version" >&2
  exit 1
fi

git fetch --quiet --force origin "refs/tags/$TAG:refs/tags/$TAG"
tag_commit=$(git rev-list -n 1 "$TAG")
head_commit=$(git rev-parse HEAD)
if [[ "$tag_commit" != "$head_commit" ]]; then
  printf 'Checkout hiện tại %s không trùng tag %s tại %s.\n' \
    "$head_commit" "$TAG" "$tag_commit" >&2
  exit 1
fi

remote_tag=$(git ls-remote --exit-code origin "refs/tags/$TAG")
if [[ -z "$remote_tag" ]]; then
  printf 'Tag chưa tồn tại trên origin: %s\n' "$TAG" >&2
  exit 1
fi

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
visibility=$(gh repo view --json visibility --jq .visibility)
if [[ "$visibility" != PUBLIC ]]; then
  printf 'Repository phải public để người dùng tải release: %s (%s)\n' \
    "$repo" "$visibility" >&2
  exit 1
fi
if gh release view "$TAG" --repo "$repo" >/dev/null 2>&1; then
  printf 'Release đã tồn tại, từ chối ghi đè: %s\n' "$TAG" >&2
  exit 1
fi

run_json=$(gh api \
  "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$tag_commit&event=push&status=success&per_page=100")
run_id=$(jq -r --arg tag "$TAG" \
  '[.workflow_runs[] | select(.head_branch == $tag)] | sort_by(.created_at) | last | .id // empty' \
  <<<"$run_json")
if [[ -z "$run_id" ]]; then
  printf 'Chưa có CI push thành công cho tag %s tại %s.\n' \
    "$TAG" "$tag_commit" >&2
  exit 1
fi

run_url=$(jq -r --argjson id "$run_id" \
  '.workflow_runs[] | select(.id == $id) | .html_url' <<<"$run_json")
work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-preview.XXXXXX")
cleanup() {
  find "$work_dir" -depth -delete
}
trap cleanup EXIT

artifact_root="$work_dir/artifacts"
staging_dir="$work_dir/release"
mkdir -p \
  "$artifact_root/android" \
  "$artifact_root/chrome-extension" \
  "$artifact_root/linux" \
  "$artifact_root/windows"
gh run download "$run_id" --repo "$repo" \
  --name "hyper-authenticator-android-apk-$tag_commit" \
  --dir "$artifact_root/android"
gh run download "$run_id" --repo "$repo" \
  --name "hyper-authenticator-linux-deb-$tag_commit" \
  --dir "$artifact_root/linux"
gh run download "$run_id" --repo "$repo" \
  --name "hyper-authenticator-windows-installer-$tag_commit" \
  --dir "$artifact_root/windows"
gh run download "$run_id" --repo "$repo" \
  --name "hyper-authenticator-chrome-extension-$tag_commit" \
  --dir "$artifact_root/chrome-extension"

REQUIRE_ANDROID_SIGNED_APK=true \
REQUIRE_CHROME_EXTENSION_PREVIEW=true \
  scripts/agent/check_github_preview_assets.sh "$artifact_root" "$staging_dir"

android_fingerprint=$(tr -d ':[:space:]' \
  < android/app-signing-certificate.sha256 | tr '[:upper:]' '[:lower:]')

notes_path="$work_dir/RELEASE_NOTES.md"
cat > "$notes_path" <<EOF
# Hyper Authenticator $TAG

Đây là **GitHub Preview** dành cho người dùng muốn thử ứng dụng trước khi dự án
hoàn tất quy trình phát hành trên các app store. Android APK đã ký bằng app
signing certificate của dự án; package Windows/Linux chưa code-sign.

## Điểm mới

- Đăng nhập là tùy chọn: không đăng nhập vẫn dùng vault local bình thường.
- Khi đăng nhập, tài khoản TOTP tự đồng bộ qua cloud và nhận tín hiệu thay đổi
  Realtime; thêm/sửa/xóa được áp dụng cho cùng tài khoản trên các thiết bị.
- Hỗ trợ import/export QR chuẩn \`otpauth\` và import Google Authenticator,
  bao gồm migration nhiều QR.
- Bổ sung ba visual style, light/dark mode và giao diện Settings gọn hơn.
- Cải thiện điều hướng, privacy shield, accessibility và trải nghiệm scanner.
- Chrome Extension tự bundle font fallback CanvasKit, không cần kết nối Google
  Fonts và vẫn giữ CSP chỉ cho phép origin Supabase cần thiết.

## Tải xuống

- Windows x64: file \`*-windows-x64-setup.exe\`.
- Linux amd64: file \`*_amd64.deb\`.
- Android: file \`*-android.apk\`; Android có thể yêu cầu cho phép cài app từ
  nguồn GitHub/browser đang dùng.
- Chrome Extension: file \`*-chrome-extension.zip\`; giải nén vào thư mục riêng,
  rồi dùng **Load unpacked** trong \`chrome://extensions\` của Chrome 114+.
- Xác minh SHA-256 bằng file checksum cạnh từng installer hoặc \`SHA256SUMS.txt\`.
- Flutter Web production: https://authenticator.hyperz.xyz/

## Cảnh báo bắt buộc

- Windows installer chưa code-sign nên Microsoft Defender SmartScreen có thể cảnh báo.
- Debian package chưa được ký qua package repository; chỉ cài khi checksum khớp.
- Android APK đã ký nhưng vẫn là preview; biometric/camera trên thiết bị thật và
  store review chưa hoàn tất. iOS và macOS chưa được đính kèm.
- Chrome Extension là **owner-waived runtime acceptance preview**: build/package,
  checksum và static security contract đã pass, nhưng clean-profile/restart/
  tamper/cross-device runtime acceptance vẫn chưa có evidence. Chỉ dùng với dữ
  liệu test hoặc bản sao có thể khôi phục; không phải Chrome Web Store release.
- SMTP production chưa được owner cấu hình; email khôi phục mật khẩu có thể chưa tới mailbox thật.
- Khi đăng nhập, mã được đồng bộ tự động qua Supabase Vault. Đây là mã hóa do
  server quản lý, không phải zero-knowledge E2EE.
- Không gửi credential qua public issue. Báo cáo lỗ hổng riêng tư tại
  https://github.com/$repo/security/advisories/new

## Provenance

- Source tag: \`$TAG\`
- Commit: \`$tag_commit\`
- CI đã pass: $run_url
- Package version: \`$package_version\`
- Android app-signing certificate SHA-256: \`$android_fingerprint\`
- Chrome Extension runtime acceptance: \`owner-waived\`
EOF

release_assets=()
while IFS= read -r value; do release_assets+=("$value"); done \
  < <(find "$staging_dir" -maxdepth 1 -type f -print | LC_ALL=C sort)

gh release create "$TAG" "${release_assets[@]}" \
  --repo "$repo" \
  --verify-tag \
  --prerelease \
  --title "Hyper Authenticator $TAG" \
  --notes-file "$notes_path"

if ! scripts/agent/verify_github_preview_release.sh \
  "$TAG" "$repo" "$tag_commit"; then
  printf '%s\n' \
    'Public verification thất bại; chuyển release về draft để fail closed.' >&2
  if ! gh release edit "$TAG" --repo "$repo" --draft; then
    printf '%s\n' \
      'CRITICAL: Không chuyển được release lỗi về draft; cần maintainer xử lý ngay.' >&2
  fi
  exit 1
fi

gh release view "$TAG" --repo "$repo" \
  --json url,isPrerelease,tagName,targetCommitish,publishedAt,assets
