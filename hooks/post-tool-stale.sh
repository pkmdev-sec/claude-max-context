#!/bin/bash
# Hook: PostToolUse — Mark project graph stale on edits, check mesh inbox
INPUT=$(cat)
source "$(dirname "$0")/_lib.sh"

TOOL=$(_json tool_name)
if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
  CWD=$(_json cwd)
  SANITIZED=$(printf '%s' "$CWD" | tr -c 'a-zA-Z0-9' '-')
  touch "$HOME/.claude/projects/${SANITIZED}/.graph-stale" 2>/dev/null
fi

# Mesh inbox check (if mesh is installed)
MESH_CONTEXT=""
if [[ -f "$HOME/.claude/mesh/hooks/mesh-post-tool.sh" ]]; then
  MESH_CONTEXT=$(bash "$HOME/.claude/mesh/hooks/mesh-post-tool.sh" <<< "$INPUT" 2>/dev/null) || true
fi

if [[ -n "$MESH_CONTEXT" ]]; then
  python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalSystemContext':sys.argv[1]}}))
" "$MESH_CONTEXT"
else
  echo '{}'
fi
