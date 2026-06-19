#!/usr/bin/env bash
set -euo pipefail

TART_RAW_URL="${TART_RAW_URL:-https://raw.githubusercontent.com/dawidpolakowski/tart/main/tart.sh}"
TART_INSTALL_DIR="${TART_INSTALL_DIR:-${HOME}/.local/bin}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
target="${TART_INSTALL_DIR}/tart"

download_tart() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TART_RAW_URL" -o "$target"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$TART_RAW_URL"
    return
  fi

  printf 'tart installer: curl or wget is required to download tart.sh\n' >&2
  exit 1
}

install_tart() {
  local local_source=""

  mkdir -p "$TART_INSTALL_DIR"

  if [[ "$(basename "$script_dir")" == "scripts" && -f "${repo_root}/tart.sh" ]]; then
    local_source="${repo_root}/tart.sh"
  fi

  if [[ -f "$local_source" ]]; then
    cp "$local_source" "$target"
  else
    download_tart
  fi

  chmod 0755 "$target"
}

path_contains_install_dir() {
  case ":${PATH}:" in
    *":${TART_INSTALL_DIR}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

print_next_steps() {
  printf 'Installed tart to %s\n' "$target"

  if path_contains_install_dir; then
    printf 'Run: tart version\n'
    return
  fi

  printf '\n%s is not currently in your PATH.\n' "$TART_INSTALL_DIR"
  printf 'Add this to your shell profile, then open a new terminal:\n\n'
  printf '  export PATH="%s:$PATH"\n\n' "$TART_INSTALL_DIR"
  printf 'Or run tart directly with:\n\n'
  printf '  %s version\n' "$target"
}

install_tart
print_next_steps
