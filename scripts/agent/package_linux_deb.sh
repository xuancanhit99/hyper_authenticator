#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUNDLE=${1:-}
OUTPUT_DIR=${2:-}

if [[ -z "$BUNDLE" || -z "$OUTPUT_DIR" ]]; then
  printf '%s\n' \
    'Usage: scripts/agent/package_linux_deb.sh BUNDLE_DIR OUTPUT_DIR' >&2
  exit 64
fi

if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'Từ chối package: Debian builder chỉ chạy trên Linux.' >&2
  exit 65
fi

for command in dpkg dpkg-deb dpkg-shlibdeps file sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Thiếu Debian packaging dependency: %s\n' "$command" >&2
    exit 69
  fi
done

BUNDLE=$(realpath "$BUNDLE")
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
EXECUTABLE="$BUNDLE/hyper_authenticator"
if [[ ! -x "$EXECUTABLE" || ! -d "$BUNDLE/lib" || ! -d "$BUNDLE/data" ]]; then
  printf '%s\n' 'Linux release bundle không đầy đủ hoặc executable không hợp lệ.' >&2
  exit 66
fi

if find "$BUNDLE" -type f \( \
  -name '.env' -o -name '*.env' -o -name '*.map' -o -name '*.debug' \
\) -print -quit | grep -q .; then
  printf '%s\n' 'Từ chối package: release bundle chứa env/source-map/debug artifact.' >&2
  exit 1
fi

VERSION=${PACKAGE_VERSION_OVERRIDE:-$(
  awk '$1 == "version:" { print $2; exit }' "$ROOT/pubspec.yaml"
)}
if [[ -z "$VERSION" ]] || ! dpkg --validate-version "$VERSION"; then
  printf 'Debian package version không hợp lệ: %s\n' "$VERSION" >&2
  exit 64
fi

binary_description=$(file -b "$EXECUTABLE")
case "$binary_description" in
  *x86-64*) ARCHITECTURE=amd64 ;;
  *aarch64*) ARCHITECTURE=arm64 ;;
  *)
    printf 'Không nhận diện được kiến trúc Linux bundle: %s\n' \
      "$binary_description" >&2
    exit 65
    ;;
esac

PACKAGE_ROOT=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-deb.XXXXXX")
METADATA_ROOT=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hyper-auth-metadata.XXXXXX")
chmod 0755 "$PACKAGE_ROOT"
cleanup() {
  find "$PACKAGE_ROOT" "$METADATA_ROOT" -depth -delete
}
trap cleanup EXIT

install -d -m 0755 \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/opt/hyper-authenticator" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/pixmaps" \
  "$METADATA_ROOT/debian"
cp -a "$BUNDLE/." "$PACKAGE_ROOT/opt/hyper-authenticator/"
chmod 0755 "$PACKAGE_ROOT/opt/hyper-authenticator/hyper_authenticator"
ln -s /opt/hyper-authenticator/hyper_authenticator \
  "$PACKAGE_ROOT/usr/bin/hyper-authenticator"
install -m 0644 "$ROOT/packaging/linux/app.hyperz.authenticator.desktop" \
  "$PACKAGE_ROOT/usr/share/applications/app.hyperz.authenticator.desktop"
install -m 0644 "$ROOT/assets/logos/hyper-logo-green-black.png" \
  "$PACKAGE_ROOT/usr/share/pixmaps/app.hyperz.authenticator.png"

printf '%s\n' \
  'Source: hyper-authenticator' \
  'Section: utils' \
  'Priority: optional' \
  'Maintainer: Hyperz' \
  'Standards-Version: 4.6.2' \
  '' \
  'Package: hyper-authenticator' \
  'Architecture: any' \
  'Description: Hyper Authenticator TOTP client' \
  > "$METADATA_ROOT/debian/control"

elf_files=()
while IFS= read -r -d '' candidate; do
  if file -b "$candidate" | grep -Eq '^ELF .* (executable|shared object)'; then
    elf_files+=("$candidate")
  fi
done < <(find "$PACKAGE_ROOT/opt/hyper-authenticator" -type f -print0)
if [[ ${#elf_files[@]} -eq 0 ]]; then
  printf '%s\n' 'Không tìm thấy ELF file trong Linux release bundle.' >&2
  exit 1
fi

pushd "$METADATA_ROOT" >/dev/null
dependency_output=$(dpkg-shlibdeps \
  --ignore-missing-info \
  -O \
  -l"$PACKAGE_ROOT/opt/hyper-authenticator/lib" \
  "${elf_files[@]}")
popd >/dev/null
DEPENDENCIES=$(sed -n 's/^shlibs:Depends=//p' <<<"$dependency_output")
if [[ -z "$DEPENDENCIES" ]] ||
  ! grep -Eq '(^|, )libc6([ ,]|$)' <<<"$DEPENDENCIES" ||
  ! grep -Eq '(^|, )libgtk-3-0(t64)?([ ,]|$)' <<<"$DEPENDENCIES" ||
  ! grep -Eq '(^|, )libsecret-1-0([ ,]|$)' <<<"$DEPENDENCIES"; then
  printf '%s\n' \
    'Dependency scan thiếu libc, GTK hoặc libsecret runtime contract.' >&2
  exit 1
fi

# Flutter engine nạp EGL/GLES/OpenGL bằng dlopen nên dpkg-shlibdeps không nhìn thấy
# ba loader này trong ELF DT_NEEDED. Giữ explicit runtime contract để package
# không chỉ vô tình chạy trên distro mới nhờ dependency gián tiếp.
for runtime_dependency in libegl1 libgles2 libgl1; do
  if ! grep -Eq \
    "(^|, )${runtime_dependency}([ (>,]|$)" <<<"$DEPENDENCIES"; then
    DEPENDENCIES="$DEPENDENCIES, $runtime_dependency"
  fi
done
# libsecret là client library; một desktop tối giản hoặc KDE/KWallet thuần không
# nhất thiết có org.freedesktop.secrets. Package kéo gnome-keyring để luôn có
# provider tương thích, còn unlock/login integration vẫn cần desktop smoke thật.
if ! grep -Eq '(^|, )gnome-keyring([ (>,]|$)' <<<"$DEPENDENCIES"; then
  DEPENDENCIES="$DEPENDENCIES, gnome-keyring"
fi

INSTALLED_SIZE=$(du -sk "$PACKAGE_ROOT" | awk '{print $1}')
MAINTAINER=${LINUX_PACKAGE_MAINTAINER:-Hyperz}
printf '%s\n' \
  'Package: hyper-authenticator' \
  "Version: $VERSION" \
  'Section: utils' \
  'Priority: optional' \
  "Architecture: $ARCHITECTURE" \
  "Maintainer: $MAINTAINER" \
  "Installed-Size: $INSTALLED_SIZE" \
  "Depends: $DEPENDENCIES" \
  'Homepage: https://authenticator.hyperz.xyz/' \
  'Description: Ứng dụng xác thực TOTP local-first đa nền tảng' \
  ' Hyper Authenticator lưu local vault trong platform secure storage và hỗ trợ' \
  ' encrypted cloud sync trên native platform.' \
  > "$PACKAGE_ROOT/DEBIAN/control"
chmod 0644 "$PACKAGE_ROOT/DEBIAN/control"

safe_version=${VERSION//:/_}
safe_version=${safe_version//\//_}
DEB_PATH="$OUTPUT_DIR/hyper-authenticator_${safe_version}_${ARCHITECTURE}.deb"
dpkg-deb --root-owner-group --build "$PACKAGE_ROOT" "$DEB_PATH" >/dev/null
dpkg-deb --info "$DEB_PATH" >/dev/null
package_contents=$(dpkg-deb --contents "$DEB_PATH")
grep -F './opt/hyper-authenticator/hyper_authenticator' \
  <<<"$package_contents" >/dev/null
root_entry=$(sed -n '1p' <<<"$package_contents")
if [[ "$root_entry" != drwxr-xr-x*' ./' ]]; then
  printf 'Debian archive root entry không phải mode 0755: %s\n' \
    "$root_entry" >&2
  exit 1
fi

CHECKSUM_PATH="$DEB_PATH.sha256"
(
  cd "$OUTPUT_DIR"
  sha256sum "$(basename "$DEB_PATH")" > "$(basename "$CHECKSUM_PATH")"
)
chmod 0644 "$DEB_PATH" "$CHECKSUM_PATH"

printf '%s\n' "✓ Debian package: $DEB_PATH"
printf '%s\n' "✓ Debian architecture: $ARCHITECTURE"
printf '%s\n' "✓ Debian dependencies: $DEPENDENCIES"
printf '%s\n' "✓ Debian checksum: $CHECKSUM_PATH"
