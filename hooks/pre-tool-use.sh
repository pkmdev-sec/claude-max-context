#!/bin/bash
# Hook: PreToolUse — Enforce parallelization + pre-commit tests
INPUT=$(cat)
source "$(dirname "$0")/_lib.sh"

ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
TOOL=$(_json tool_name)

# Read-only tools: instant pass
case "$TOOL" in
  Read|Glob|Grep|Agent|WebSearch|WebFetch|TaskCreate|TaskGet|TaskList|TaskUpdate|TaskStop|TaskOutput|AskUserQuestion|LSP|Skill|NotebookEdit)
    echo "$ALLOW"; exit 0 ;;
esac

CWD=$(_json cwd)
SANITIZED=$(printf '%s' "$CWD" | tr -c 'a-zA-Z0-9' '-')
PROJECT_DIR="$HOME/.claude/projects/${SANITIZED}"
TRACKER="$PROJECT_DIR/.edit-dirs"

if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" ]]; then
  # Skip enforcement for worktree agents
  _GIT_COMMON=$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)
  _GIT_DIR=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)
  [[ -n "${_GIT_COMMON:-}" && -n "${_GIT_DIR:-}" && "$_GIT_COMMON" != "$_GIT_DIR" ]] && { echo "$ALLOW"; exit 0; }

  mkdir -p "$PROJECT_DIR"
  FILE_PATH=$(_json file_path)
  [[ -z "$FILE_PATH" ]] && FILE_PATH=$(_json filePath)
  if [[ -n "$FILE_PATH" ]]; then
    REL_PATH="${FILE_PATH#$CWD/}"
    TOP_DIR=$(printf '%s' "$REL_PATH" | cut -d'/' -f1-2)
    [[ -n "$TOP_DIR" && "$TOP_DIR" == *"/"* ]] && printf '%s\n' "$TOP_DIR" >> "$TRACKER" 2>/dev/null
  fi

  if [[ -f "$TRACKER" ]]; then
    TOTAL_EDITS=$(wc -l < "$TRACKER" | tr -d ' ')
    UNIQUE_DIRS=$(sort -u "$TRACKER" | wc -l | tr -d ' ')
    if [[ "$TOTAL_EDITS" -ge 5 && "$UNIQUE_DIRS" -ge 3 ]]; then
      DIR_LIST=$(sort -u "$TRACKER" | tr '\n' ', ' | sed 's/,$//')
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Sequential multi-directory editing denied ($TOTAL_EDITS edits across $UNIQUE_DIRS dirs: $DIR_LIST). Use TeamCreate with parallel teammates instead.\"}}"
      exit 0
    fi
  fi
  echo "$ALLOW"; exit 0
fi

if [[ "$TOOL" == "Bash" && "$INPUT" == *git*commit* ]]; then
  CMD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
  if printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)git\s+commit\b'; then
    TEST_CMD=""
    [[ -f "$CWD/package.json" ]] && TEST_CMD="cd $CWD && npm test 2>&1 | tail -30"
    [[ -f "$CWD/Cargo.toml" ]] && TEST_CMD="cd $CWD && cargo test 2>&1 | tail -30"
    [[ -f "$CWD/go.mod" ]] && TEST_CMD="cd $CWD && go test ./... 2>&1 | tail -30"
    [[ -f "$CWD/pyproject.toml" ]] && TEST_CMD="cd $CWD && python -m pytest --tb=short 2>&1 | tail -30"
    if [[ -n "$TEST_CMD" ]] && ! eval "$TEST_CMD" >/dev/null 2>&1; then
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Pre-commit tests failed. Fix before committing.\"}}"
      exit 0
    fi
  fi
fi

echo "$ALLOW"
