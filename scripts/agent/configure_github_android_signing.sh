#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
KEYSTORE_PATH=${1:-"$HOME/.hyper-authenticator/signing/android/hyper-authenticator-app-signing.jks"}
KEY_ALIAS=${2:-hyper-authenticator}
REPOSITORY=${3:-xuancanhit99/hyper_authenticator}
CONFIRMATION=${4:-}
EXPECTED_CONFIRMATION=UPLOAD_ANDROID_SIGNING_SECRETS
FINGERPRINT_FILE="$ROOT/android/app-signing-certificate.sha256"

usage() {
  printf '%s\n' \
    'Usage: scripts/agent/configure_github_android_signing.sh [KEYSTORE_PATH] [KEY_ALIAS] [OWNER/REPO] CONFIRMATION' \
    "Confirmation bắt buộc: $EXPECTED_CONFIRMATION" >&2
}

if [[ "$CONFIRMATION" != "$EXPECTED_CONFIRMATION" ]]; then
  usage
  exit 64
fi
if [[ ! -t 0 || ! -t 1 ]]; then
  printf '%s\n' 'Cần terminal tương tác để nhập password bằng prompt ẩn.' >&2
  exit 64
fi
if [[ ! "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf '%s\n' 'GitHub repository không hợp lệ.' >&2
  exit 64
fi
for command in gh keytool base64 awk tr; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu GitHub signing dependency: %s\n' "$command" >&2
    exit 69
  fi
done
if [[ ! -f "$KEYSTORE_PATH" || -L "$KEYSTORE_PATH" ]]; then
  printf '%s\n' 'Keystore phải là regular file, không phải symlink.' >&2
  exit 66
fi
if file_mode=$(stat -f '%Lp' "$KEYSTORE_PATH" 2>/dev/null); then
  :
else
  file_mode=$(stat -c '%a' "$KEYSTORE_PATH")
fi
if (( (8#$file_mode & 077) != 0 )); then
  printf 'Keystore phải có mode 0600 hoặc chặt hơn; hiện tại là %s.\n' \
    "$file_mode" >&2
  exit 77
fi
gh auth status >/dev/null
gh repo view "$REPOSITORY" --json nameWithOwner --jq .nameWithOwner >/dev/null

expected_fingerprint=$(tr -d ':[:space:]' < "$FINGERPRINT_FILE" | tr '[:upper:]' '[:lower:]')
if [[ ! "$expected_fingerprint" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' 'Fingerprint pin trong repository không hợp lệ.' >&2
  exit 65
fi
printf 'Nhập keystore password: ' >&2
IFS= read -r -s store_password
printf '\nNhập key password (Enter nếu giống keystore password): ' >&2
IFS= read -r -s key_password
printf '\n' >&2
if [[ -z "$key_password" ]]; then
  key_password=$store_password
fi
if [[ -z "$store_password" || -z "$key_password" ]]; then
  printf '%s\n' 'Password không được rỗng.' >&2
  exit 64
fi

export HYPER_AUTH_ANDROID_STORE_PASSWORD=$store_password
keytool_output=$(keytool -J-Duser.language=en -list -v \
  -keystore "$KEYSTORE_PATH" \
  -storepass:env HYPER_AUTH_ANDROID_STORE_PASSWORD \
  -alias "$KEY_ALIAS" 2>/dev/null) || {
    unset HYPER_AUTH_ANDROID_STORE_PASSWORD store_password key_password
    printf '%s\n' 'Không mở được keystore hoặc không tìm thấy alias.' >&2
    exit 1
  }
actual_fingerprint=$(awk -F': ' '/SHA256:/{print $2; exit}' <<<"$keytool_output" |
  tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
unset keytool_output HYPER_AUTH_ANDROID_STORE_PASSWORD
if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
  unset store_password key_password
  printf '%s\n' 'Certificate fingerprint không khớp pin của project.' >&2
  exit 1
fi

base64 < "$KEYSTORE_PATH" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPOSITORY"
printf '%s' "$KEY_ALIAS" | gh secret set ANDROID_KEY_ALIAS --repo "$REPOSITORY"
printf '%s' "$store_password" | gh secret set ANDROID_STORE_PASSWORD --repo "$REPOSITORY"
printf '%s' "$key_password" | gh secret set ANDROID_KEY_PASSWORD --repo "$REPOSITORY"
unset store_password key_password

printf '✓ Đã cập nhật 4 Android signing secrets cho %s.\n' "$REPOSITORY"
printf '✓ App signing certificate SHA-256: %s\n' "$expected_fingerprint"
printf '%s\n' 'GitHub chỉ nhận keystore qua encrypted Actions secret; artifact không chứa key.'
