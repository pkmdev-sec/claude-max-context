#!/bin/bash
set -euo pipefail
source "$HOME/.claude/mesh/lib/core.sh"
NAME="${1:-$(mesh_random_name)}"
CWD="${2:-$(pwd)}"
PID="$$"
mesh_registry_update '. + {($n): {pid:($p|tonumber),cwd:$c,status:"active",registered_at:$t,last_heartbeat:$t}}' \
  --arg n "$NAME" --arg p "$PID" --arg c "$CWD" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$MESH_CHANNELS/$NAME/.cursors"
touch "$MESH_CHANNELS/$NAME/inbox.jsonl" "$MESH_CHANNELS/$NAME/outbox.jsonl"
echo '{}' > "$MESH_CHANNELS/$NAME/status.json"
echo "$NAME" > "$MESH_DIR/registry/.my-name.$PID"
echo "$NAME"
