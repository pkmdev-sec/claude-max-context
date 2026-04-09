#!/bin/bash
source "$HOME/.claude/mesh/lib/core.sh"
CWD="${1:-$(pwd)}"
bash "$HOME/.claude/mesh/bin/mesh-gc.sh" >/dev/null 2>&1 || true
NAME=$(bash "$HOME/.claude/mesh/bin/mesh-register.sh" "" "$CWD" 2>/dev/null)
[[ -z "$NAME" ]] && exit 0
echo "[MESH] Identity: $NAME"
PEERS=$(jq -r 'to_entries[]|select(.value.status=="active")|select(.key!="'"$NAME"'")|"  \(.key) — \(.value.cwd // "unknown")"' "$MESH_REGISTRY" 2>/dev/null)
[[ -n "$PEERS" ]] && echo "[MESH] Peers:" && echo "$PEERS" || echo "[MESH] No other active sessions."
echo "$NAME" > "$MESH_DIR/registry/.latest-name"
