#!/usr/bin/env bash
# lib/tokens.sh — Detect token limits, select optimization profile
# This is the fallback engine: detect what the user has access to and adapt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

# ─── Token Limit Detection ───────────────────────────────────────

detect_model_from_settings() {
  local settings_file
  settings_file="$(claude_home)/settings.json"
  if [[ -f "$settings_file" ]]; then
    local model
    model=$(jq -r '.model // empty' "$settings_file" 2>/dev/null)
    [[ -n "$model" ]] && echo "$model" && return 0
  fi
  echo ""
}

detect_model_from_env() {
  echo "${ANTHROPIC_MODEL:-${CLAUDE_MODEL:-}}"
}

resolve_model() {
  local model
  model=$(detect_model_from_env)
  [[ -n "$model" ]] && echo "$model" && return 0
  model=$(detect_model_from_settings)
  [[ -n "$model" ]] && echo "$model" && return 0
  echo "unknown"
}

# Map model identifier to context window size
model_to_context_window() {
  local model="$1"
  case "$model" in
    *"[1m]"*|*"-1m"*|*"context-1m"*)
      echo "1000000" ;;
    *"opus"*)
      echo "200000" ;;
    *"sonnet"*)
      echo "200000" ;;
    *"haiku"*)
      echo "200000" ;;
    *)
      echo "200000" ;;  # Conservative default
  esac
}

# Check for explicit user override
get_user_context_override() {
  echo "${CLAUDE_CONTEXT_WINDOW:-}"
}

# Master function: determine effective context window
detect_context_window() {
  # Priority 1: Explicit user override
  local override
  override=$(get_user_context_override)
  if [[ -n "$override" ]]; then
    echo "$override"
    return 0
  fi

  # Priority 2: Detect from model
  local model
  model=$(resolve_model)
  local window
  window=$(model_to_context_window "$model")
  echo "$window"
}

# ─── Profile Selection ────────────────────────────────────────────

# Returns: "1m" or "200k" or "conservative"
select_profile() {
  local window
  window=$(detect_context_window)

  if [[ "$window" -ge 900000 ]]; then
    echo "1m"
  elif [[ "$window" -ge 180000 ]]; then
    echo "200k"
  else
    echo "conservative"
  fi
}

# Generate env vars for the selected profile
profile_env_vars() {
  local profile="$1"
  case "$profile" in
    1m)
      cat << 'ENVBLOCK'
CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95
CLAUDE_CODE_MAX_OUTPUT_TOKENS=32768
CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE=999000
CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP=1
ENABLE_CLAUDE_CODE_SM_COMPACT=1
USE_API_CONTEXT_MANAGEMENT=1
CLAUDE_CODE_FORCE_GLOBAL_CACHE=1
CLAUDE_CODE_SAVE_HOOK_ADDITIONAL_CONTEXT=1
CLAUDE_CODE_DISABLE_FAST_MODE=1
CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1
CLAUDE_ENABLE_STREAM_WATCHDOG=1
CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES=1
CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING=1
BASH_MAX_OUTPUT_LENGTH=150000
API_TIMEOUT_MS=600000
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
ENVBLOCK
      ;;
    200k)
      cat << 'ENVBLOCK'
CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=92
CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384
CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE=199000
CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP=1
ENABLE_CLAUDE_CODE_SM_COMPACT=1
USE_API_CONTEXT_MANAGEMENT=1
CLAUDE_CODE_FORCE_GLOBAL_CACHE=1
CLAUDE_CODE_SAVE_HOOK_ADDITIONAL_CONTEXT=1
CLAUDE_CODE_DISABLE_FAST_MODE=1
CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1
CLAUDE_ENABLE_STREAM_WATCHDOG=1
CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES=1
CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING=1
BASH_MAX_OUTPUT_LENGTH=150000
API_TIMEOUT_MS=600000
ENVBLOCK
      ;;
    conservative|*)
      cat << 'ENVBLOCK'
CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=85
CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384
CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE=160000
CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP=1
ENABLE_CLAUDE_CODE_SM_COMPACT=1
CLAUDE_CODE_FORCE_GLOBAL_CACHE=1
CLAUDE_CODE_SAVE_HOOK_ADDITIONAL_CONTEXT=1
CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1
CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
BASH_MAX_OUTPUT_LENGTH=100000
API_TIMEOUT_MS=300000
ENVBLOCK
      ;;
  esac
}

# Human-readable profile description
describe_profile() {
  local profile="$1"
  case "$profile" in
    1m)
      echo "1M Context (Opus [1m]) — 950K usable, compaction at 95%, max capacity"
      ;;
    200k)
      echo "200K Context (Standard) — 184K usable, compaction at 92%, balanced"
      ;;
    conservative)
      echo "Conservative (<200K) — 136K usable, compaction at 85%, max safety"
      ;;
  esac
}

# Profile-specific compaction math for context management instructions
profile_context_math() {
  local profile="$1"
  case "$profile" in
    1m)
      cat << 'MATH'
Context window: 1,000,000 tokens
Auto-compaction trigger: 950,000 tokens (95%)
Output reserve: 32,768 tokens
Blocking limit: 999,000 tokens
Effective capacity: ~918K tokens
MATH
      ;;
    200k)
      cat << 'MATH'
Context window: 200,000 tokens
Auto-compaction trigger: 184,000 tokens (92%)
Output reserve: 16,384 tokens
Blocking limit: 199,000 tokens
Effective capacity: ~167K tokens
MATH
      ;;
    conservative)
      cat << 'MATH'
Context window: ~200,000 tokens (assumed)
Auto-compaction trigger: 170,000 tokens (85%)
Output reserve: 16,384 tokens
Blocking limit: 160,000 tokens
Effective capacity: ~136K tokens
MATH
      ;;
  esac
}

# Allow running standalone for diagnostics
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "═══ Token Limit Diagnostics ═══"
  echo "Model (env):      $(detect_model_from_env || echo 'not set')"
  echo "Model (settings):  $(detect_model_from_settings || echo 'not found')"
  echo "Model (resolved):  $(resolve_model)"
  echo "Context window:    $(detect_context_window)"
  echo "Profile:           $(select_profile)"
  echo "Description:       $(describe_profile "$(select_profile)")"
  echo ""
  echo "─── Profile Math ───"
  profile_context_math "$(select_profile)"
  echo ""
  echo "─── Environment Variables ───"
  profile_env_vars "$(select_profile)"
fi
