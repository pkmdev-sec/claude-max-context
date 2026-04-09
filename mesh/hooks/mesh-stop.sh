#!/bin/bash
NAME="${CLAUDE_MESH_NAME:-}"
[[ -z "$NAME" ]] && NAME=$(cat "$HOME/.claude/mesh/registry/.latest-name" 2>/dev/null || true)
[[ -z "$NAME" ]] && exit 0
REG_PID=$(jq -r ".\"$NAME\".pid // empty" "$HOME/.claude/mesh/registry/sessions.json" 2>/dev/null)
if [[ -n "$REG_PID" ]] && kill -0 "$REG_PID" 2>/dev/null; then
  [[ "$REG_PID" != "$$" && "$REG_PID" != "$PPID" ]] && exit 0
fi
bash "$HOME/.claude/mesh/bin/mesh-deregister.sh" "$NAME" 2>/dev/null || true
