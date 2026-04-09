#!/usr/bin/env bash
# lib/platform.sh — Platform detection and path resolution
# All functions are pure (no side effects) and safe to source multiple times.
set -euo pipefail

detect_os() {
  case "$(uname -s)" in
    Darwin*)  echo "macos" ;;
    Linux*)   echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)        echo "unknown" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64)  echo "x64" ;;
    *)             echo "$(uname -m)" ;;
  esac
}

detect_shell() {
  basename "${SHELL:-/bin/bash}"
}

shell_profile_path() {
  local shell_name
  shell_name=$(detect_shell)
  case "$shell_name" in
    zsh)  echo "${HOME}/.zshrc" ;;
    bash)
      if [[ -f "${HOME}/.bash_profile" ]]; then
        echo "${HOME}/.bash_profile"
      else
        echo "${HOME}/.bashrc"
      fi
      ;;
    fish) echo "${HOME}/.config/fish/config.fish" ;;
    *)    echo "${HOME}/.profile" ;;
  esac
}

claude_home() {
  echo "${CLAUDE_HOME:-${HOME}/.claude}"
}

claude_bin_dir() {
  local home
  home=$(claude_home)
  echo "${home}/bin"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  local cmd="$1"
  local install_hint="${2:-}"
  if ! has_command "$cmd"; then
    echo "ERROR: Required command '$cmd' not found."
    [[ -n "$install_hint" ]] && echo "  Install: $install_hint"
    return 1
  fi
}

require_jq() {
  local os
  os=$(detect_os)
  case "$os" in
    macos)  require_command jq "brew install jq" ;;
    linux)  require_command jq "sudo apt-get install -y jq  OR  sudo yum install -y jq" ;;
    *)      require_command jq "See https://jqlang.github.io/jq/download/" ;;
  esac
}

min_bash_version() {
  local required="${1:-4}"
  local current="${BASH_VERSINFO[0]:-3}"
  if [[ "$current" -lt "$required" ]]; then
    echo "WARNING: Bash $required+ recommended (you have $current). Some features may not work."
    return 1
  fi
}

is_ci() {
  [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${BUILDKITE:-}" ]] || [[ -n "${CIRCLECI:-}" ]]
}
