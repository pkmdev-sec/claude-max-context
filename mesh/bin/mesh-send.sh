#!/bin/bash
set -euo pipefail
source "$HOME/.claude/mesh/lib/core.sh"
TO="${1:?Usage: mesh-send.sh <peer> <type> <message>}"; TYPE="${2:-heads-up}"; PAYLOAD="${3:-}"
NAME=$(mesh_my_name)
MSG=$(mesh_make_msg "$NAME" "$TO" "$TYPE" "$PAYLOAD")
mesh_atomic_append "$MESH_CHANNELS/$TO/inbox.jsonl" "$MSG"
mesh_atomic_append "$MESH_GLOBAL_LOG" "$MSG"
echo "Sent $TYPE to $TO"
