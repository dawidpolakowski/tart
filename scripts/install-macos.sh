#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'tart macOS installer must be run on macOS.\n' >&2
  exit 2
fi

TART_INSTALL_DIR="${TART_INSTALL_DIR:-${HOME}/.local/bin}"
TART_MACOS_APP_DIR="${TART_MACOS_APP_DIR:-${HOME}/Applications}"
TART_MACOS_SUPPORT_DIR="${TART_MACOS_SUPPORT_DIR:-${HOME}/Library/Application Support/tart}"
TART_MACOS_ARCHIVE_URL="${TART_MACOS_ARCHIVE_URL:-https://github.com/dawidpolakowski/tart/releases/latest/download/tart-macos.tar.gz}"
TART_SKIP_DESKTOP="${TART_SKIP_DESKTOP:-0}"
TART_SKIP_NPM_INSTALL="${TART_SKIP_NPM_INSTALL:-0}"

script_dir="$(pwd)"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

repo_root="$(cd "${script_dir}/.." 2>/dev/null && pwd || pwd)"
stage_dir=""
package_source=""

cleanup() {
  if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
    rm -rf "$stage_dir"
  fi
}

trap cleanup EXIT

download_file() {
  local url="$1"
  local target="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$target"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$url"
    return
  fi

  printf 'tart macOS installer: curl or wget is required.\n' >&2
  exit 1
}

local_package_available() {
  [[ -f "${repo_root}/tart.sh" && -f "${repo_root}/package.json" && -d "${repo_root}/desktop" ]]
}

download_release_package() {
  local archive extracted

  stage_dir="$(mktemp -d)"
  archive="${stage_dir}/tart-macos.tar.gz"

  printf 'Downloading tart macOS package...\n'
  download_file "$TART_MACOS_ARCHIVE_URL" "$archive"
  tar -xzf "$archive" -C "$stage_dir"

  extracted="$(find "$stage_dir" -mindepth 1 -maxdepth 1 -type d -name 'tart-*' -print | head -n 1)"
  if [[ -z "$extracted" || ! -d "$extracted" ]]; then
    printf 'tart macOS installer: release archive did not contain a tart package.\n' >&2
    exit 1
  fi

  package_source="$extracted"
}

resolve_package_source() {
  if local_package_available; then
    package_source="$repo_root"
    return
  fi

  download_release_package
}

install_cli() {
  mkdir -p "$TART_INSTALL_DIR"
  cp "${package_source}/tart.sh" "${TART_INSTALL_DIR}/tart"
  chmod 0755 "${TART_INSTALL_DIR}/tart"
}

copy_file_if_exists() {
  local source="$1"
  local target="$2"

  if [[ -f "$source" ]]; then
    cp "$source" "$target"
  fi
}

copy_dir() {
  local source="$1"
  local target="$2"

  rm -rf "$target"
  cp -R "$source" "$target"
}

install_desktop_files() {
  mkdir -p "$TART_MACOS_SUPPORT_DIR"

  copy_file_if_exists "${package_source}/README.md" "$TART_MACOS_SUPPORT_DIR/"
  copy_file_if_exists "${package_source}/package.json" "$TART_MACOS_SUPPORT_DIR/"
  copy_file_if_exists "${package_source}/package-lock.json" "$TART_MACOS_SUPPORT_DIR/"
  cp "${package_source}/tart.sh" "$TART_MACOS_SUPPORT_DIR/"
  cp "${package_source}/tart-desktop" "$TART_MACOS_SUPPORT_DIR/"
  copy_dir "${package_source}/assets" "${TART_MACOS_SUPPORT_DIR}/assets"
  copy_dir "${package_source}/desktop" "${TART_MACOS_SUPPORT_DIR}/desktop"

  chmod 0755 "${TART_MACOS_SUPPORT_DIR}/tart.sh" "${TART_MACOS_SUPPORT_DIR}/tart-desktop"
}

install_desktop_dependencies() {
  if [[ "$TART_SKIP_NPM_INSTALL" == "1" ]]; then
    printf 'Skipped desktop dependency install because TART_SKIP_NPM_INSTALL=1.\n'
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    printf 'npm was not found. The CLI is installed, but the desktop app needs Node.js and npm.\n' >&2
    printf 'After installing Node.js, run: cd "%s" && npm install\n' "$TART_MACOS_SUPPORT_DIR" >&2
    return
  fi

  printf 'Installing desktop dependencies...\n'
  if [[ -f "${TART_MACOS_SUPPORT_DIR}/package-lock.json" ]]; then
    (cd "$TART_MACOS_SUPPORT_DIR" && npm ci)
  else
    (cd "$TART_MACOS_SUPPORT_DIR" && npm install)
  fi
}

write_app_launcher() {
  local launcher="$1"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"\n'
    printf 'TART_SUPPORT_DIR=%q\n' "$TART_MACOS_SUPPORT_DIR"
    printf 'exec "${TART_SUPPORT_DIR}/tart-desktop" "$@"\n'
  } > "$launcher"
  chmod 0755 "$launcher"
}

write_info_plist() {
  local plist="$1"

  cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>tart</string>
  <key>CFBundleExecutable</key>
  <string>tart</string>
  <key>CFBundleIconFile</key>
  <string>tart-clock-icon</string>
  <key>CFBundleIdentifier</key>
  <string>com.tart.desktop</string>
  <key>CFBundleName</key>
  <string>tart</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>0.2.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
}

create_app_bundle() {
  local app_bundle="${TART_MACOS_APP_DIR}/tart.app"
  local contents="${app_bundle}/Contents"

  mkdir -p "${contents}/MacOS" "${contents}/Resources"
  write_app_launcher "${contents}/MacOS/tart"
  write_info_plist "${contents}/Info.plist"

  if [[ -f "${TART_MACOS_SUPPORT_DIR}/assets/tart-clock-icon.icns" ]]; then
    cp "${TART_MACOS_SUPPORT_DIR}/assets/tart-clock-icon.icns" "${contents}/Resources/tart-clock-icon.icns"
  fi
}

path_contains_install_dir() {
  case ":${PATH}:" in
    *":${TART_INSTALL_DIR}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

print_next_steps() {
  printf '\nInstalled tart CLI to %s\n' "${TART_INSTALL_DIR}/tart"

  if ! path_contains_install_dir; then
    printf '\n%s is not currently in your PATH.\n' "$TART_INSTALL_DIR"
    printf 'Add this to your shell profile, then open a new terminal:\n\n'
    printf '  export PATH="%s:$PATH"\n' "$TART_INSTALL_DIR"
  fi

  if [[ "$TART_SKIP_DESKTOP" != "1" ]]; then
    printf '\nInstalled tart desktop app to %s\n' "${TART_MACOS_APP_DIR}/tart.app"
    printf 'Open it from Finder, or run:\n\n'
    printf '  open "%s"\n' "${TART_MACOS_APP_DIR}/tart.app"
  fi

  printf '\nCheck the CLI with:\n\n'
  printf '  tart version\n'
}

resolve_package_source
install_cli

if [[ "$TART_SKIP_DESKTOP" != "1" ]]; then
  install_desktop_files
  install_desktop_dependencies
  create_app_bundle
fi

print_next_steps
