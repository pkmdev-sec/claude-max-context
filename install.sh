#!/usr/bin/env bash
# install.sh — Global installer for Claude Infinite Context
# Run: bash install.sh [--profile 1m|200k|conservative] [--dry-run] [--uninstall]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/lib/platform.sh"
source "$REPO_DIR/lib/tokens.sh"

CLAUDE_DIR="$(claude_home)"
BACKUP_DIR="${CLAUDE_DIR}/backups/ic-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
UNINSTALL=false
FORCE_PROFILE=""
MANIFEST_FILE="${CLAUDE_DIR}/.infinite-context-manifest"

log()  { echo "  $1"; }
ok()   { echo "  ✅ $1"; }
warn() { echo "  ⚠️  $1"; }
err()  { echo "  ❌ $1"; }
die()  { err "$1"; exit 1; }

# ─── Argument parsing ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)  FORCE_PROFILE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    -h|--help)
      echo "Usage: install.sh [--profile 1m|200k|conservative] [--dry-run] [--uninstall]"
      echo "  --profile   Force a specific profile (auto-detected by default)"
      echo "  --dry-run   Show what would be done without making changes"
      echo "  --uninstall Remove all installed components"
      exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ─── Uninstall ────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
  echo "═══ Uninstalling Claude Infinite Context ═══"
  if [[ -f "$MANIFEST_FILE" ]]; then
    while IFS= read -r file; do
      if [[ -f "$file" ]]; then
        log "Removing $file"
        $DRY_RUN || rm -f "$file"
      fi
    done < "$MANIFEST_FILE"
    $DRY_RUN || rm -f "$MANIFEST_FILE"
    ok "Uninstall complete. Backups preserved in $CLAUDE_DIR/backups/"
  else
    warn "No manifest found — nothing to uninstall."
  fi
  exit 0
fi

# ─── Pre-flight ───────────────────────────────────────────────
echo "═══ Claude Infinite Context — Installer ═══"
echo ""
source "$REPO_DIR/lib/validate.sh"
run_preflight || die "Pre-flight failed. Fix errors above before installing."
echo ""

# ─── Profile selection ────────────────────────────────────────
PROFILE="${FORCE_PROFILE:-$(select_profile)}"
echo "Profile: $PROFILE — $(describe_profile "$PROFILE")"
echo ""

# ─── Backup ───────────────────────────────────────────────────
echo "─── Backing up existing config ───"
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$BACKUP_DIR"
  for f in settings.json CLAUDE.md; do
    [[ -f "$CLAUDE_DIR/$f" ]] && cp "$CLAUDE_DIR/$f" "$BACKUP_DIR/$f" && log "Backed up $f"
  done
  [[ -d "$CLAUDE_DIR/hooks" ]] && cp -r "$CLAUDE_DIR/hooks" "$BACKUP_DIR/hooks" && log "Backed up hooks/"
  [[ -d "$CLAUDE_DIR/mesh" ]] && cp -r "$CLAUDE_DIR/mesh" "$BACKUP_DIR/mesh" && log "Backed up mesh/"
  ok "Backup: $BACKUP_DIR"
else
  log "[dry-run] Would backup to $BACKUP_DIR"
fi
echo ""

# ─── Install manifest tracking ───────────────────────────────
MANIFEST=()
track() { MANIFEST+=("$1"); }

# ─── Create directories ──────────────────────────────────────
echo "─── Creating directories ───"
for d in hooks mesh/lib mesh/hooks mesh/bin projects compaction-state context-logs agent-results; do
  target="$CLAUDE_DIR/$d"
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$target"
  fi
  log "$target"
done
echo ""

# ─── Install hooks ────────────────────────────────────────────
echo "─── Installing hooks ───"
for hook_file in "$REPO_DIR"/hooks/*.sh; do
  fname=$(basename "$hook_file")
  target="$CLAUDE_DIR/hooks/$fname"
  if [[ "$DRY_RUN" == false ]]; then
    cp "$hook_file" "$target"
    chmod +x "$target"
  fi
  track "$target"
  log "$fname"
done
ok "Hooks installed"
echo ""

# ─── Install mesh ─────────────────────────────────────────────
echo "─── Installing mesh ───"
for f in "$REPO_DIR"/mesh/lib/*.sh; do
  target="$CLAUDE_DIR/mesh/lib/$(basename "$f")"
  $DRY_RUN || { cp "$f" "$target"; chmod +x "$target"; }
  track "$target"
done
for f in "$REPO_DIR"/mesh/hooks/*.sh; do
  target="$CLAUDE_DIR/mesh/hooks/$(basename "$f")"
  $DRY_RUN || { cp "$f" "$target"; chmod +x "$target"; }
  track "$target"
done
for f in "$REPO_DIR"/mesh/bin/*.sh; do
  target="$CLAUDE_DIR/mesh/bin/$(basename "$f")"
  $DRY_RUN || { cp "$f" "$target"; chmod +x "$target"; }
  track "$target"
done
ok "Mesh system installed"
echo ""

# ─── Generate settings.json ──────────────────────────────────
echo "─── Generating settings.json ───"
PROFILE_FILE="$REPO_DIR/config/profiles/${PROFILE}.json"
MODEL=$(jq -r '.model' "$PROFILE_FILE")

# Build env block from profile
ENV_LINES=""
while IFS='=' read -r key value; do
  [[ -z "$key" ]] && continue
  ENV_LINES="${ENV_LINES}    \"${key}\": \"${value}\",\n"
done < <(profile_env_vars "$PROFILE")
# Remove trailing comma
ENV_LINES=$(printf '%b' "$ENV_LINES" | sed '$ s/,$//')

SETTINGS_TARGET="$CLAUDE_DIR/settings.json"
if [[ "$DRY_RUN" == false ]]; then
  # Read template and substitute
  sed -e "s|{{MODEL}}|${MODEL}|g" "$REPO_DIR/config/templates/settings.json.tpl" | \
    awk -v env="$ENV_LINES" '{gsub(/\{\{ENV_BLOCK\}\}/, env); print}' > "$SETTINGS_TARGET"
  # Validate JSON
  if ! jq empty "$SETTINGS_TARGET" 2>/dev/null; then
    err "Generated settings.json is invalid JSON — restoring backup"
    [[ -f "$BACKUP_DIR/settings.json" ]] && cp "$BACKUP_DIR/settings.json" "$SETTINGS_TARGET"
    die "Settings generation failed"
  fi
  track "$SETTINGS_TARGET"
fi
ok "settings.json generated (model: $MODEL)"
echo ""

# ─── Generate CLAUDE.md ──────────────────────────────────────
echo "─── Generating CLAUDE.md ───"
CONTEXT_MATH=$(profile_context_math "$PROFILE")
CLAUDE_MD_TARGET="$CLAUDE_DIR/CLAUDE.md"
if [[ "$DRY_RUN" == false ]]; then
  cat > "$CLAUDE_MD_TARGET" << CLAUDEMD
# Global Instructions for Claude Code

## Authorization
Operate fully autonomously. All file operations, git operations, package installs, and shell commands within the working directory are pre-authorized. I review via git diff.

## Reasoning
For every non-trivial task: think deeply before acting. Analyze the problem, consider multiple approaches, evaluate tradeoffs, identify edge cases. Show complete reasoning. Never truncate code or use stubs.

## Output
Lead with analysis, then implementation. Always show complete code. Explain why for architecture decisions, root cause for bugs. No preamble, no summaries.

## Context Management
$CONTEXT_MATH

After compaction, these survive: summary text, up to 5 recently-read files, plan files, CLAUDE.md + memory.
To maximize survival: read critical files explicitly, use /plan for long sessions, save discoveries to memory.

## Memory
Auto-save useful info: architectural decisions, non-obvious patterns, failed approaches, conventions. Verify memories against current code before acting on them.

## Coding Standards
- Production-grade: error handling at boundaries, input validation, typed interfaces
- Security-first: no command injection, no unsafe evals, no hardcoded secrets
- No TODO comments — implement or raise explicitly

## Code Quality
Avoid generic variable names, over-commenting obvious code, blanket try/catch. Use domain-specific names, comment the WHY, target error handling at actual failure points.

## Scaling Rules
- 1 file: do it directly
- 2-5 files same module: use Task tool fork
- 5-20 files: parallel agents per module
- 20+ files: use TeamCreate with worktree isolation
- NEVER attempt 20+ file changes sequentially
CLAUDEMD
  track "$CLAUDE_MD_TARGET"
fi
ok "CLAUDE.md generated"
echo ""

# ─── Generate env-setup.sh ───────────────────────────────────
echo "─── Generating env-setup.sh ───"
ENV_TARGET="$CLAUDE_DIR/env-setup.sh"
if [[ "$DRY_RUN" == false ]]; then
  {
    echo '#!/usr/bin/env bash'
    echo "# Claude Infinite Context — Environment ($PROFILE profile)"
    echo "# Source: source ~/.claude/env-setup.sh"
    echo ""
    profile_env_vars "$PROFILE" | while IFS='=' read -r key value; do
      [[ -n "$key" ]] && echo "export ${key}=${value}"
    done
    echo ""
    echo "# Verification"
    echo 'echo "✅ Claude context optimization loaded ('"$PROFILE"' profile)"'
  } > "$ENV_TARGET"
  chmod +x "$ENV_TARGET"
  track "$ENV_TARGET"
fi
ok "env-setup.sh generated"

# Add source line to shell profile if not already present
SHELL_PROFILE=$(shell_profile_path)
SOURCE_LINE='source "$HOME/.claude/env-setup.sh"'
if [[ "$DRY_RUN" == false ]]; then
  if ! grep -qF "claude/env-setup.sh" "$SHELL_PROFILE" 2>/dev/null; then
    echo "" >> "$SHELL_PROFILE"
    echo "# Claude Infinite Context" >> "$SHELL_PROFILE"
    echo "$SOURCE_LINE" >> "$SHELL_PROFILE"
    log "Added source line to $SHELL_PROFILE"
  else
    log "Source line already in $SHELL_PROFILE"
  fi
fi
echo ""

# ─── Write manifest ──────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
  printf '%s\n' "${MANIFEST[@]}" > "$MANIFEST_FILE"
fi

# ─── Verify ──────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  echo "─── Dry-run complete (no changes made) ───"
  echo ""
  echo "═══════════════════════════════════════════"
  echo "  ✅ Dry-run finished. Run without --dry-run to install."
  exit 0
fi

echo "─── Verification ───"
ERRORS=0
[[ -f "$CLAUDE_DIR/settings.json" ]] && jq empty "$CLAUDE_DIR/settings.json" 2>/dev/null && ok "settings.json valid" || { err "settings.json invalid"; ((ERRORS++)); }
[[ -f "$CLAUDE_DIR/CLAUDE.md" ]] && ok "CLAUDE.md exists" || { err "CLAUDE.md missing"; ((ERRORS++)); }
[[ -x "$CLAUDE_DIR/hooks/session-start.sh" ]] && ok "Hooks executable" || { err "Hooks not executable"; ((ERRORS++)); }
[[ -x "$CLAUDE_DIR/mesh/lib/core.sh" ]] && ok "Mesh installed" || { err "Mesh missing"; ((ERRORS++)); }
[[ -f "$CLAUDE_DIR/env-setup.sh" ]] && ok "env-setup.sh exists" || { err "env-setup.sh missing"; ((ERRORS++)); }
echo ""

if [[ "$ERRORS" -gt 0 ]]; then
  err "$ERRORS verification error(s). Rolling back..."
  if [[ -d "$BACKUP_DIR" && "$DRY_RUN" == false ]]; then
    for f in settings.json CLAUDE.md; do
      [[ -f "$BACKUP_DIR/$f" ]] && cp "$BACKUP_DIR/$f" "$CLAUDE_DIR/$f"
    done
    [[ -d "$BACKUP_DIR/hooks" ]] && cp -r "$BACKUP_DIR/hooks/"* "$CLAUDE_DIR/hooks/" 2>/dev/null || true
  fi
  die "Installation failed. Previous config restored from backup."
fi

echo "═══════════════════════════════════════════"
ok "Installation complete!"
echo ""
echo "  Profile:  $PROFILE"
echo "  Backup:   $BACKUP_DIR"
echo "  Manifest: $MANIFEST_FILE"
echo ""
echo "  Next: Open a new terminal (or run: source $SHELL_PROFILE)"
echo "        Then start Claude Code normally."
echo ""
echo "  To uninstall: bash $REPO_DIR/install.sh --uninstall"
