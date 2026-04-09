#!/bin/bash
INPUT="${1:-$(cat)}"
source "$HOME/.claude/mesh/lib/core.sh"
NAME=$(mesh_my_name); [[ -z "$NAME" ]] && exit 0
SESS_DIR="$MESH_CHANNELS/$NAME"
[[ -d "$SESS_DIR" ]] || { mkdir -p "$SESS_DIR/.cursors"; touch "$SESS_DIR/inbox.jsonl" "$SESS_DIR/outbox.jsonl"; }

_val() { local _t="${INPUT#*\"$1\":\"}"; [[ "$_t" != "$INPUT" ]] && printf '%s' "${_t%%\"*}"; }
TOOL=$(_val tool_name); FILE_PATH=$(_val file_path)

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mesh_registry_update 'if .[$n] then .[$n].last_heartbeat=$ts else . end' --arg n "$NAME" --arg ts "$TS" 2>/dev/null || true

if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]] && [[ -n "$FILE_PATH" ]]; then
  MSG=$(mesh_make_msg "$NAME" "*" "status-update" "$TOOL: $FILE_PATH")
  mesh_atomic_append "$SESS_DIR/outbox.jsonl" "$MSG"
  mesh_atomic_append "$MESH_GLOBAL_LOG" "$MSG"
  for pd in "$MESH_CHANNELS"/*/; do
    P=$(basename "$pd"); [[ "$P" == "$NAME" ]] && continue
    [[ -f "$pd/status.json" ]] && jq -e --arg f "$FILE_PATH" '.recent_files//[]|index($f)' "$pd/status.json" >/dev/null 2>&1 && {
      W=$(mesh_make_msg "system" "$NAME" "conflict-warning" "Both $NAME and $P editing $FILE_PATH")
      mesh_atomic_append "$SESS_DIR/inbox.jsonl" "$W"
    }
  done
fi

# Check inbox
INBOX="$SESS_DIR/inbox.jsonl"; CURSOR_F="$SESS_DIR/.cursors/inbox.offset"
OFFSET=$(cat "$CURSOR_F" 2>/dev/null || echo 0)
FSIZE=$(stat -f%z "$INBOX" 2>/dev/null || stat -c%s "$INBOX" 2>/dev/null || echo 0)
CTX=""
if [[ "$FSIZE" -gt "$OFFSET" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    P=$(echo "$line" | jq -r '"[MESH:\(.type) from \(.from)] \(.payload)"' 2>/dev/null)
    [[ -n "$P" ]] && CTX="${CTX}${P}\n"
  done < <(tail -c +$((OFFSET+1)) "$INBOX")
  echo "$FSIZE" > "$CURSOR_F"
fi
[[ -n "$CTX" ]] && printf '%b' "$CTX"
