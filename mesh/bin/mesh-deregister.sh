#!/bin/bash
set -euo pipefail
source "$HOME/.claude/mesh/lib/core.sh"
NAME="${1:?Usage: mesh-deregister.sh <name>}"
mesh_registry_update 'del(.[$n])' --arg n "$NAME"
rm -f "$MESH_DIR/registry/.my-name."* 2>/dev/null
