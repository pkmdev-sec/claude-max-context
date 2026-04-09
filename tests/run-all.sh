#!/usr/bin/env bash
# tests/run-all.sh — End-to-end verification suite
# Tests: syntax, profiles, fallback logic, benchmark math, hook contracts, installer
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1"; }

echo "═══ Claude Max Context — Test Suite ═══"
echo ""

# ── 1. Syntax validation ─────────────────────────────────────
echo "── 1. Script syntax ──"
for f in lib/platform.sh lib/validate.sh lib/tokens.sh lib/benchmark.sh install.sh; do
  bash -n "$REPO_DIR/$f" 2>/dev/null && pass "$f" || fail "$f: syntax error"
done
for f in "$REPO_DIR"/hooks/*.sh "$REPO_DIR"/mesh/lib/*.sh "$REPO_DIR"/mesh/hooks/*.sh "$REPO_DIR"/mesh/bin/*.sh; do
  bash -n "$f" 2>/dev/null && pass "$(basename "$f")" || fail "$(basename "$f"): syntax error"
done
echo ""

# ── 2. Profile JSON ──────────────────────────────────────────
echo "── 2. Profile validity ──"
for p in "$REPO_DIR"/config/profiles/*.json; do
  nm=$(basename "$p")
  if jq empty "$p" 2>/dev/null; then
    ok=true
    for fld in name context_window compact_pct output_tokens blocking_limit model; do
      [[ -z "$(jq -r ".$fld // empty" "$p")" ]] && { fail "$nm: missing $fld"; ok=false; }
    done
    $ok && pass "$nm"
  else
    fail "$nm: invalid JSON"
  fi
done
echo ""

# ── 3. Fallback logic ────────────────────────────────────────
echo "── 3. Token detection & fallback ──"
source "$REPO_DIR/lib/tokens.sh"

# Override respected
r=$(CLAUDE_CONTEXT_WINDOW=500000 detect_context_window)
[[ "$r" == "500000" ]] && pass "CLAUDE_CONTEXT_WINDOW override → $r" || fail "override: got $r"

# Model mapping
r=$(model_to_context_window "opus[1m]")
[[ "$r" == "1000000" ]] && pass "opus[1m] → 1000000" || fail "opus[1m]: got $r"

r=$(model_to_context_window "unknown-xyz")
[[ "$r" == "200000" ]] && pass "unknown model → 200000 (conservative default)" || fail "unknown: got $r"

# Profile thresholds
r=$(CLAUDE_CONTEXT_WINDOW=1000000 select_profile)
[[ "$r" == "1m" ]] && pass "1M window → 1m profile" || fail "1M: got $r"

r=$(CLAUDE_CONTEXT_WINDOW=200000 select_profile)
[[ "$r" == "200k" ]] && pass "200K window → 200k profile" || fail "200K: got $r"

r=$(CLAUDE_CONTEXT_WINDOW=100000 select_profile)
[[ "$r" == "conservative" ]] && pass "100K window → conservative profile" || fail "100K: got $r"

# Env vars generated for all profiles
for pr in 1m 200k conservative; do
  vars=$(profile_env_vars "$pr")
  [[ -n "$vars" ]] && echo "$vars" | grep -q "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" \
    && pass "$pr: env vars with compact override" \
    || fail "$pr: missing env vars"
done
echo ""

# ── 4. Benchmark math ────────────────────────────────────────
echo "── 4. Benchmark math (from source v2.1.92) ──"
source "$REPO_DIR/lib/benchmark.sh"

# Kc = window - min(output, 20000)
r=$(calc_kc 1000000 20000)
[[ "$r" == "980000" ]] && pass "Kc(1M, 20K) = 980000" || fail "Kc: expected 980000 got $r"

r=$(calc_kc 200000 16384)
[[ "$r" == "183616" ]] && pass "Kc(200K, 16384) = 183616" || fail "Kc: expected 183616 got $r"

# d88 = min(Kc * pct/100, Kc - 13000)
r=$(calc_auto_compact 980000 70)
[[ "$r" == "686000" ]] && pass "d88(980K, 70%) = 686000" || fail "d88: expected 686000 got $r"

r=$(calc_auto_compact 980000 95)
[[ "$r" == "931000" ]] && pass "d88(980K, 95%) = 931000" || fail "d88: expected 931000 got $r"

[[ "$STOCK_PCT" == "70" ]] && pass "stock pct=70% (from source)" || fail "stock pct=$STOCK_PCT"
[[ "$K47" == "13000" ]] && pass "K47=13000 (from source)" || fail "K47=$K47"
[[ "$UNDERSCORE_47" == "3000" ]] && pass "_47=3000 (from source)" || fail "_47=$UNDERSCORE_47"

# Gain is positive for all profiles
for pr in 1m 200k conservative; do
  out=$(compare_profile "$pr" 2>/dev/null)
  gain=$(echo "$out" | grep "Gain before" | grep -oE '\+[0-9]+' | tr -d '+')
  [[ -n "$gain" && "$gain" -gt 0 ]] && pass "$pr: +${gain} tokens" || fail "$pr: non-positive gain"
done
echo ""

# ── 5. Hook I/O contracts ────────────────────────────────────
echo "── 5. Hook I/O contracts ──"

# pre-tool-use: Read → allow, valid JSON
out=$(echo '{"tool_name":"Read","tool_input":{},"cwd":"/tmp"}' | bash "$REPO_DIR/hooks/pre-tool-use.sh" 2>/dev/null)
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1 \
  && pass "pre-tool-use: Read → allow" || fail "pre-tool-use: unexpected output"

# pre-compact: returns preservation instructions
out=$(echo '{"session_id":"t","cwd":"/tmp"}' | bash "$REPO_DIR/hooks/pre-compact.sh" 2>/dev/null)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && pass "pre-compact: preservation instructions" || fail "pre-compact: missing instructions"

# post-tool-stale: returns valid JSON
out=$(echo '{"tool_name":"Grep","cwd":"/tmp"}' | bash "$REPO_DIR/hooks/post-tool-stale.sh" 2>/dev/null)
echo "$out" | jq empty 2>/dev/null \
  && pass "post-tool-stale: valid JSON" || fail "post-tool-stale: invalid output"

# _lib.sh: _json extraction works
out=$(INPUT='{"tool_name":"Edit","cwd":"/foo"}' bash -c 'source "'"$REPO_DIR"'/hooks/_lib.sh"; echo $(_json tool_name)' 2>/dev/null)
[[ "$out" == "Edit" ]] && pass "_lib.sh _json: extracts tool_name" || fail "_lib.sh: got '$out'"
echo ""

# ── 6. Template rendering ────────────────────────────────────
echo "── 6. Settings template ──"
tpl="$REPO_DIR/config/templates/settings.json.tpl"
grep -q "{{MODEL}}" "$tpl" && grep -q "{{ENV_BLOCK}}" "$tpl" \
  && pass "template has placeholders" || fail "template missing placeholders"

rendered=$(sed 's/{{MODEL}}/opus/g; s/{{ENV_BLOCK}}/"TEST": "1"/g' "$tpl")
echo "$rendered" | jq empty 2>/dev/null \
  && pass "rendered template: valid JSON" || fail "rendered template: invalid JSON"
echo ""

# ── 7. Installer dry-run ─────────────────────────────────────
echo "── 7. Installer ──"
bash "$REPO_DIR/install.sh" --dry-run --profile 200k >/dev/null 2>&1 \
  && pass "install.sh --dry-run exits 0" || fail "install.sh --dry-run failed"
echo ""

# ── Summary ───────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo "═══════════════════════════════════════════"
echo "  $PASS passed, $FAIL failed ($TOTAL total)"
if [[ "$FAIL" -gt 0 ]]; then
  echo "  ❌ FAILURES FOUND"
  exit 1
else
  echo "  ✅ ALL TESTS PASSED"
fi
