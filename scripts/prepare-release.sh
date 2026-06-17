#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
  printf 'usage: %s <version-tag> <output-dir>\n' "${0##*/}" >&2
  exit 2
fi

readonly VERSION_TAG="$1"
readonly OUTPUT_DIR="$2"
readonly RELEASE_URL_BASE="https://github.com/dawidpolakowski/tart/releases/download/${VERSION_TAG}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
stage_dir="$(mktemp -d)"
package_root="${stage_dir}/tart-${VERSION_TAG}"

cleanup() {
  rm -rf "$stage_dir"
}

trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$package_root/assets" "$package_root/desktop" "$package_root/scripts"

cp "${repo_root}/README.md" "$package_root/"
cp "${repo_root}/package.json" "$package_root/"
if [[ -f "${repo_root}/package-lock.json" ]]; then
  cp "${repo_root}/package-lock.json" "$package_root/"
fi
cp "${repo_root}/tart.sh" "$package_root/"
cp "${repo_root}/tart-desktop" "$package_root/"
cp "${repo_root}/scripts/install.sh" "$package_root/scripts/"
cp "${repo_root}/scripts/install-macos.sh" "$package_root/scripts/"
cp "${repo_root}/scripts/install.ps1" "$package_root/scripts/"
cp "${repo_root}/desktop/index.html" "$package_root/desktop/"
cp "${repo_root}/desktop/main.cjs" "$package_root/desktop/"
cp "${repo_root}/desktop/preload.cjs" "$package_root/desktop/"
cp "${repo_root}/desktop/renderer.cjs" "$package_root/desktop/"
cp "${repo_root}/desktop/styles.css" "$package_root/desktop/"
cp "${repo_root}/desktop/tart-core.cjs" "$package_root/desktop/"
cp "${repo_root}/assets/tart-icon.gif" "$package_root/assets/"
cp "${repo_root}/assets/tart-icon.png" "$package_root/assets/"
cp "${repo_root}/assets/tart-clock-icon.icns" "$package_root/assets/"
cp "${repo_root}/assets/tart-clock-icon.ico" "$package_root/assets/"
cp "${repo_root}/assets/tart-clock-icon.png" "$package_root/assets/"
cp "${repo_root}/assets/tart-icon-key.gif" "$package_root/assets/"
cp "${repo_root}/assets/tart-icon-key.png" "$package_root/assets/"

chmod 0755 "$package_root/tart.sh" "$package_root/tart-desktop" "$package_root/scripts/install.sh" "$package_root/scripts/install-macos.sh"

sed \
  "s|https://raw.githubusercontent.com/dawidpolakowski/tart/main/tart.sh|${RELEASE_URL_BASE}/tart.sh|g" \
  "${repo_root}/scripts/install.sh" > "${OUTPUT_DIR}/install.sh"
chmod 0755 "${OUTPUT_DIR}/install.sh"

sed \
  "s|https://github.com/dawidpolakowski/tart/releases/latest/download/tart-macos.tar.gz|${RELEASE_URL_BASE}/tart-macos.tar.gz|g" \
  "${repo_root}/scripts/install-macos.sh" > "${OUTPUT_DIR}/install-macos.sh"
chmod 0755 "${OUTPUT_DIR}/install-macos.sh"

sed \
  "s|https://raw.githubusercontent.com/dawidpolakowski/tart/main/tart.sh|${RELEASE_URL_BASE}/tart.sh|g" \
  "${repo_root}/scripts/install.ps1" > "${OUTPUT_DIR}/install.ps1"

cp "${repo_root}/tart.sh" "${OUTPUT_DIR}/tart.sh"
chmod 0755 "${OUTPUT_DIR}/tart.sh"

tar -C "$stage_dir" -czf "${OUTPUT_DIR}/tart-${VERSION_TAG}-linux.tar.gz" "tart-${VERSION_TAG}"
cp "${OUTPUT_DIR}/tart-${VERSION_TAG}-linux.tar.gz" "${OUTPUT_DIR}/tart-linux.tar.gz"

tar -C "$stage_dir" -czf "${OUTPUT_DIR}/tart-${VERSION_TAG}-macos.tar.gz" "tart-${VERSION_TAG}"
cp "${OUTPUT_DIR}/tart-${VERSION_TAG}-macos.tar.gz" "${OUTPUT_DIR}/tart-macos.tar.gz"

(
  cd "$stage_dir"
  zip -qr "${OUTPUT_DIR}/tart-${VERSION_TAG}-windows.zip" "tart-${VERSION_TAG}"
)
cp "${OUTPUT_DIR}/tart-${VERSION_TAG}-windows.zip" "${OUTPUT_DIR}/tart-windows.zip"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 \
    install.sh \
    install-macos.sh \
    install.ps1 \
    tart.sh \
    "tart-${VERSION_TAG}-linux.tar.gz" \
    "tart-${VERSION_TAG}-macos.tar.gz" \
    "tart-${VERSION_TAG}-windows.zip" \
    tart-linux.tar.gz \
    tart-macos.tar.gz \
    tart-windows.zip \
    > SHA256SUMS.txt
)
