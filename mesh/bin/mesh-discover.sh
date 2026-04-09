#!/bin/bash
set -euo pipefail
source "$HOME/.claude/mesh/lib/core.sh"
mesh_reap_stale
echo "=== Active Sessions ==="
jq -r 'to_entries[]|select(.value.status=="active")|"\(.key)\t\(.value.cwd)\t\(.value.working_on//"idle")"' "$MESH_REGISTRY" 2>/dev/null | \
  while IFS=$'\t' read -r n c w; do printf "  %-20s %-40s %s\n" "$n" "$c" "$w"; done
echo ""; jq '[to_entries[]|select(.value.status=="active")]|length' "$MESH_REGISTRY" 2>/dev/null | xargs -I{} echo "{} active session(s)"
