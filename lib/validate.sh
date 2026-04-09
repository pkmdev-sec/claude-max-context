#!/usr/bin/env bash
# lib/validate.sh — Pre-flight checks for Claude Code installation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

validate_claude_installed() {
  if has_command claude; then
    local ver
    ver=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    echo "OK: Claude Code found ($ver)"
    return 0
  fi
  echo "ERROR: Claude Code CLI not found in PATH."
  echo "  Install: npm install -g @anthropic-ai/claude-code"
  echo "  Or: https://docs.anthropic.com/en/docs/claude-code"
  return 1
}

validate_api_key() {
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "OK: ANTHROPIC_API_KEY is set"
    return 0
  fi
  # Check if Claude Code has its own auth (OAuth, etc.)
  local claude_config="${HOME}/.claude/.claude.json"
  if [[ -f "$claude_config" ]]; then
    echo "OK: Claude Code config found (may have OAuth auth)"
    return 0
  fi
  echo "WARNING: No ANTHROPIC_API_KEY set and no Claude config found."
  echo "  Claude Code may prompt for authentication on first use."
  return 0  # Not fatal — Claude Code handles auth interactively
}

validate_jq() {
  if has_command jq; then
    echo "OK: jq found ($(jq --version 2>&1))"
    return 0
  fi
  echo "ERROR: jq is required but not installed."
  require_jq
  return 1
}

validate_git() {
  if has_command git; then
    echo "OK: git found ($(git --version 2>&1 | head -1))"
    return 0
  fi
  echo "WARNING: git not found. Some features (branch detection, handoff) disabled."
  return 0
}

validate_python3() {
  if has_command python3; then
    echo "OK: python3 found ($(python3 --version 2>&1))"
    return 0
  fi
  echo "WARNING: python3 not found. JSON parsing in hooks will use jq fallback."
  return 0
}

validate_permissions() {
  local claude_dir
  claude_dir=$(claude_home)
  if [[ -d "$claude_dir" ]]; then
    if [[ -w "$claude_dir" ]]; then
      echo "OK: $claude_dir is writable"
      return 0
    fi
    echo "ERROR: $claude_dir exists but is not writable"
    return 1
  fi
  # Directory doesn't exist yet — check parent
  local parent_dir
  parent_dir=$(dirname "$claude_dir")
  if [[ -w "$parent_dir" ]]; then
    echo "OK: Can create $claude_dir"
    return 0
  fi
  echo "ERROR: Cannot create $claude_dir (parent not writable)"
  return 1
}

run_preflight() {
  echo "═══ Pre-flight Validation ═══"
  local errors=0
  validate_claude_installed || ((errors++))
  validate_api_key         || true  # Non-fatal
  validate_jq              || ((errors++))
  validate_git             || true  # Non-fatal
  validate_python3         || true  # Non-fatal
  validate_permissions     || ((errors++))
  echo "═══════════════════════════════"
  if [[ "$errors" -gt 0 ]]; then
    echo "❌ $errors critical error(s) found. Fix them before installing."
    return 1
  fi
  echo "✅ All pre-flight checks passed."
  return 0
}

# Allow running standalone
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_preflight
fi
