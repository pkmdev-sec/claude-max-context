#!/bin/bash
# Mesh core library — filesystem-based IPC between Claude sessions

MESH_DIR="$HOME/.claude/mesh"
MESH_REGISTRY="$MESH_DIR/registry/sessions.json"
MESH_REGISTRY_LOCK="$MESH_DIR/registry/.lock.d"
MESH_CHANNELS="$MESH_DIR/channels"
MESH_GLOBAL_LOG="$MESH_CHANNELS/global.jsonl"

mkdir -p "$MESH_DIR/registry" "$MESH_CHANNELS" 2>/dev/null
[[ -f "$MESH_REGISTRY" ]] || echo '{}' > "$MESH_REGISTRY"
[[ -f "$MESH_GLOBAL_LOG" ]] || touch "$MESH_GLOBAL_LOG"

[[ -f "$MESH_DIR/lib/names.sh" ]] && source "$MESH_DIR/lib/names.sh"

_mesh_lock() {
  local lock_dir="$1" max_wait=50 i=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    ((i++)); [[ $i -ge $max_wait ]] && { rm -rf "$lock_dir"; mkdir "$lock_dir"; return 0; }; sleep 0.05
  done
}
_mesh_unlock() { rmdir "$1" 2>/dev/null; }

mesh_atomic_append() { printf '%s\n' "$2" >> "$1"; }

mesh_registry_update() {
  local filter="$1"; shift
  _mesh_lock "$MESH_REGISTRY_LOCK"
  local tmp; tmp=$(mktemp "${MESH_REGISTRY}.XXXXXX")
  if jq "$@" "$filter" "$MESH_REGISTRY" > "$tmp" 2>/dev/null; then mv "$tmp" "$MESH_REGISTRY"; else rm -f "$tmp"; fi
  _mesh_unlock "$MESH_REGISTRY_LOCK"
}

mesh_my_name() {
  local pid="$$" ppid="$PPID"
  [[ -f "$MESH_DIR/registry/.my-name.$pid" ]] && { cat "$MESH_DIR/registry/.my-name.$pid"; return; }
  while [[ "$ppid" -gt 1 ]]; do
    [[ -f "$MESH_DIR/registry/.my-name.$ppid" ]] && { cat "$MESH_DIR/registry/.my-name.$ppid"; return; }
    ppid=$(ps -o ppid= -p "$ppid" 2>/dev/null | tr -d ' '); [[ -z "$ppid" ]] && break
  done
  cat "$MESH_DIR/registry/.latest-name" 2>/dev/null || echo ""
}

mesh_make_msg() {
  local from="$1" to="$2" type="$3" payload="$4" ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -cn --arg id "m_$(echo -n "${from}${ts}${RANDOM}" | shasum -a 256 2>/dev/null | head -c 8 || echo "${RANDOM}")" \
    --arg from "$from" --arg to "$to" --arg ts "$ts" --arg type "$type" --arg payload "$payload" \
    '{id:$id,from:$from,to:$to,ts:$ts,type:$type,payload:$payload}'
}

mesh_reap_stale() {
  [[ -f "$MESH_REGISTRY" ]] || return 0
  local entries; entries=$(jq -r 'to_entries[]|select(.value.pid!=null)|select(.value.status=="active")|"\(.key) \(.value.pid)"' "$MESH_REGISTRY" 2>/dev/null)
  [[ -z "$entries" ]] && return 0
  while IFS=' ' read -r name pid; do
    [[ -z "$name" || -z "$pid" ]] && continue
    kill -0 "$pid" 2>/dev/null || mesh_registry_update 'del(.[$name])' --arg name "$name"
  done <<< "$entries"
}
