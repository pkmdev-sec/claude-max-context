#!/bin/bash
# Hook: SessionStart — Bootstrap context from persistent state
# Loads: HANDOFF.md (previous session), MEMORY.md (persistent), PROJECT_MAP.md
INPUT=$(cat)
source "$(dirname "$0")/_lib.sh"

CWD=$(_json cwd)
GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
DATE=$(date "+%Y-%m-%d %H:%M %Z")
SANITIZED=$(printf '%s' "$CWD" | tr -c 'a-zA-Z0-9' '-')
PROJECT_DIR="$HOME/.claude/projects/${SANITIZED}"
MEMORY_PATH="${PROJECT_DIR}/memory/MEMORY.md"
HANDOFF_PATH="${PROJECT_DIR}/HANDOFF.md"
MAP_PATH="${PROJECT_DIR}/PROJECT_MAP.md"
STALE_PATH="${PROJECT_DIR}/.graph-stale"

rm -f "${PROJECT_DIR}/.edit-dirs" 2>/dev/null

LINES=()
LINES+=("Date: $DATE | CWD: $CWD")
[[ -n "$GIT_BRANCH" ]] && LINES+=("Git branch: $GIT_BRANCH")
[[ -f "$MEMORY_PATH" ]] && LINES+=("Project memory: $MEMORY_PATH — check before starting work.")

if [[ -f "$MAP_PATH" ]] && [[ ! -f "$STALE_PATH" ]]; then
  LINES+=("") && LINES+=("=== PROJECT MAP ===")
  LINES+=("$(head -80 "$MAP_PATH")")
  LINES+=("=== END PROJECT MAP ===")
fi

if [[ -f "$HANDOFF_PATH" ]]; then
  LINES+=("") && LINES+=("=== PREVIOUS SESSION HANDOFF ===")
  LINES+=("$(head -30 "$HANDOFF_PATH")")
  LINES+=("=== END HANDOFF ===")
  LINES+=("Continue from where the last session left off.")
fi

# Mesh registration (if mesh is installed)
if [[ -f "$HOME/.claude/mesh/hooks/mesh-session-start.sh" ]]; then
  MESH_CTX=$(bash "$HOME/.claude/mesh/hooks/mesh-session-start.sh" "$CWD" 2>/dev/null) || true
  if [[ -n "${MESH_CTX:-}" ]]; then
    LINES+=("") && LINES+=("=== MESH ===") && LINES+=("$MESH_CTX") && LINES+=("=== END MESH ===")
  fi
fi

CONTEXT=$(printf '%s\n' "${LINES[@]}")
python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput':{'hookEventName':'SessionStart','additionalContext':sys.argv[1]}}))
" "$CONTEXT"
