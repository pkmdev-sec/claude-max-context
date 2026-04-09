#!/usr/bin/env bash
# lib/benchmark.sh — Verified measurement from Claude Code v2.1.92 source
#
# The formulas below match Claude Code's actual compaction logic.
# Constants and functions identified from the published npm package source.
#
# Evidence chain:
#   d$Y=20000, K47=13000, _47=3000
#   Kc(model,exp) = window - min(output_tokens, d$Y)
#   d88(model,exp) = min(Kc * pct/100, Kc - K47)  [auto-compact threshold]
#   blocking = OVERRIDE || (Kc - _47)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"
source "$SCRIPT_DIR/tokens.sh"

# ─── Constants from Claude Code v2.1.92 ──────────────────────
D_DOLLAR_Y=20000   # max output token cap in Kc()
K47=13000           # auto-compact buffer
UNDERSCORE_47=3000  # blocking limit buffer
STOCK_PCT=70        # default auto-compact percentage (no override)

# ─── The actual formulas ─────────────────────────────────────
# Kc(model) = window - min(output_tokens, 20000)
calc_kc() {
  local window="$1" output_tokens="$2"
  local capped=$(( output_tokens < D_DOLLAR_Y ? output_tokens : D_DOLLAR_Y ))
  echo $(( window - capped ))
}

# d88() = min(Kc * pct/100, Kc - K47)
calc_auto_compact() {
  local kc="$1" pct="$2"
  local by_pct=$(( kc * pct / 100 ))
  local by_buffer=$(( kc - K47 ))
  echo $(( by_pct < by_buffer ? by_pct : by_buffer ))
}

# blocking = Kc - _47 (unless overridden)
calc_blocking() {
  local kc="$1"
  echo $(( kc - UNDERSCORE_47 ))
}

# ─── Profile comparison ──────────────────────────────────────
compare_profile() {
  local profile="$1"
  local pfile="$SCRIPT_DIR/../config/profiles/${profile}.json"
  local window compact_pct output_tokens blocking_override
  window=$(jq -r '.context_window' "$pfile")
  compact_pct=$(jq -r '.compact_pct' "$pfile")
  output_tokens=$(jq -r '.output_tokens' "$pfile")
  blocking_override=$(jq -r '.blocking_limit' "$pfile")

  # Stock (no overrides, stock output tokens capped at 20K)
  local stock_kc=$(calc_kc "$window" 20000)
  local stock_compact=$(calc_auto_compact "$stock_kc" "$STOCK_PCT")
  local stock_block=$(calc_blocking "$stock_kc")

  # Optimized (with our overrides)
  local opt_kc=$(calc_kc "$window" "$output_tokens")
  local opt_compact=$(calc_auto_compact "$opt_kc" "$compact_pct")

  local gain=$(( opt_compact - stock_compact ))
  local mult="1.0"
  [[ "$stock_compact" -gt 0 ]] && mult=$(awk "BEGIN {printf \"%.2f\", $opt_compact / $stock_compact}")

  echo "PROFILE: $profile"
  echo ""
  echo "  Source: @anthropic-ai/claude-code v2.1.92"
  echo ""
  echo "                     STOCK (no config)   WITH OVERRIDES"
  echo "  Context window:    $(printf '%9s' "$(printf "%'d" "$window")")          $(printf '%9s' "$(printf "%'d" "$window")")"
  echo "  Output cap (Kc):   $(printf '%9s' "$(printf "%'d" "$stock_kc")")          $(printf '%9s' "$(printf "%'d" "$opt_kc")")"
  echo "  Auto-compact at:   $(printf '%9s' "$(printf "%'d" "$stock_compact")")          $(printf '%9s' "$(printf "%'d" "$opt_compact")")"
  echo "  Blocking limit:    $(printf '%9s' "$(printf "%'d" "$stock_block")")          $(printf '%9s' "$(printf "%'d" "$blocking_override")")"
  echo ""
  echo "  Gain before compaction: +$(printf "%'d" "$gain") tokens (${mult}×)"
}

# ─── What the hooks add (not quantifiable as tokens) ─────────
describe_hook_value() {
  echo "BEYOND TOKEN MATH"
  echo ""
  echo "  The compaction-delay numbers above are the provable part."
  echo "  The bigger value is in things we can't reduce to a token count:"
  echo ""
  echo "  • pre-compact.sh — tells the compactor what to preserve"
  echo "    (7-point instruction list injected before compaction)"
  echo "  • DISABLE_PRECOMPACT_SKIP=1 — forces full transcript read"
  echo "    (stock skips parts of the conversation for speed)"
  echo "  • HANDOFF.md — session state persists to disk, next session loads it"
  echo "  • CLAUDE.md — behavioral instructions survive compaction"
  echo "  • SM_COMPACT — session memory gets its own compaction cycle"
  echo ""
  echo "  These make post-compaction sessions feel continuous rather"
  echo "  than starting cold. That's the real UX improvement — it's just"
  echo "  not expressible as a multiplier."
}

# ─── Verify installed values ──────────────────────────────────
verify_installation() {
  local claude_dir errors=0 checks=0
  claude_dir=$(claude_home)
  local settings="$claude_dir/settings.json"

  echo "VERIFIED ON THIS MACHINE"
  echo ""

  for item in \
    "settings.json:$claude_dir/settings.json:file" \
    "CLAUDE.md:$claude_dir/CLAUDE.md:file" \
    "env-setup.sh:$claude_dir/env-setup.sh:file" \
    "hooks/session-start.sh:$claude_dir/hooks/session-start.sh:exec" \
    "hooks/pre-compact.sh:$claude_dir/hooks/pre-compact.sh:exec" \
    "hooks/pre-tool-use.sh:$claude_dir/hooks/pre-tool-use.sh:exec" \
    "hooks/stop-handoff.sh:$claude_dir/hooks/stop-handoff.sh:exec" \
    "mesh/lib/core.sh:$claude_dir/mesh/lib/core.sh:exec"; do
    local name="${item%%:*}" rest="${item#*:}" path="${rest%%:*}" check="${rest##*:}"
    ((checks++))
    if [[ "$check" == "exec" ]]; then
      [[ -x "$path" ]] && echo "  ✅ $name" || { echo "  ❌ $name"; ((errors++)); }
    else
      [[ -f "$path" ]] && echo "  ✅ $name" || { echo "  ❌ $name"; ((errors++)); }
    fi
  done

  # Check critical env vars in settings
  if [[ -f "$settings" ]]; then
    for key in CLAUDE_AUTOCOMPACT_PCT_OVERRIDE CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP ENABLE_CLAUDE_CODE_SM_COMPACT; do
      ((checks++))
      local val=$(jq -r ".env.${key} // empty" "$settings" 2>/dev/null)
      [[ -n "$val" ]] && echo "  ✅ $key=$val" || { echo "  ❌ $key missing"; ((errors++)); }
    done
  fi

  echo ""
  echo "  $checks checked, $((checks - errors)) passed, $errors failed"
  return $errors
}

# ─── Full report ──────────────────────────────────────────────
full_report() {
  echo "══════════════════════════════════════════════════════════"
  echo "  Claude Max Context — Verification Report"
  echo "  $(date '+%Y-%m-%d %H:%M %Z')"
  echo "══════════════════════════════════════════════════════════"
  echo ""

  echo "── TOKEN MATH (from source, not estimates) ──"
  echo ""
  for p in 1m 200k conservative; do
    compare_profile "$p"
    echo ""
  done

  echo "── HOOK VALUE (not quantifiable) ──"
  echo ""
  describe_hook_value
  echo ""

  local claude_dir=$(claude_home)
  if [[ -f "$claude_dir/settings.json" ]]; then
    echo "── INSTALLATION CHECK ──"
    echo ""
    verify_installation || true
    echo ""
  fi

  echo "══════════════════════════════════════════════════════════"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-full}" in
    full)    full_report ;;
    profile) compare_profile "${2:-$(select_profile)}" ;;
    verify)  verify_installation ;;
    hooks)   describe_hook_value ;;
    *)       echo "Usage: benchmark.sh [full|profile <name>|verify|hooks]" ;;
  esac
fi
