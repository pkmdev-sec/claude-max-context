#!/bin/bash
# Hook: Stop — Save session state to HANDOFF.md for next session
INPUT=$(cat)
source "$(dirname "$0")/_lib.sh"

CWD=$(_json cwd)
SESSION_ID=$(_json session_id)
LAST_MSG=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('last_assistant_message','')[:2000])" 2>/dev/null || echo "")

SANITIZED=$(printf '%s' "$CWD" | tr -c 'a-zA-Z0-9' '-')
HANDOFF_DIR="$HOME/.claude/projects/${SANITIZED}"
mkdir -p "$HANDOFF_DIR"

DATE=$(date "+%Y-%m-%d %H:%M %Z")
GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "none")
GIT_STATUS=$(git -C "$CWD" status --short 2>/dev/null | head -10 || echo "")
GIT_DIFF_STAT=$(git -C "$CWD" diff --stat 2>/dev/null | tail -1 || echo "")

cat > "${HANDOFF_DIR}/HANDOFF.md" << HANDOFF
# Session Handoff — ${DATE}
## Session: ${SESSION_ID}  Branch: ${GIT_BRANCH}  CWD: ${CWD}

## Last Context
${LAST_MSG}

## Working State
${GIT_DIFF_STAT}

## Modified Files
${GIT_STATUS}
HANDOFF

# Mesh deregister
[[ -f "$HOME/.claude/mesh/hooks/mesh-stop.sh" ]] && bash "$HOME/.claude/mesh/hooks/mesh-stop.sh" 2>/dev/null || true

python3 -c "import json; print(json.dumps({'systemMessage':'Session handoff saved.'}))"
