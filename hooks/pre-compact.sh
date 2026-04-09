#!/bin/bash
# Hook: PreCompact — Inject preservation instructions before compaction
# This is the CRITICAL hook. It tells the compaction LLM what to keep.
INPUT=$(cat)
source "$(dirname "$0")/_lib.sh"

read -r -d '' INSTRUCTIONS << 'INST' || true
Compaction instructions — preserve these in the summary:

1. TASK STATE: What the user asked for, what's completed, what remains. Include file paths and line numbers.
2. ARCHITECTURAL DECISIONS: Design choices and WHY they were chosen over alternatives.
3. DISCOVERED PATTERNS: Codebase conventions, naming patterns, file organization found during exploration.
4. FAILED APPROACHES: What was tried and didn't work, and why — prevent repeating mistakes.
5. KEY FILE CONTENTS: Important function signatures, data structures, API shapes from recently-read files.
6. CURRENT WORKING STATE: Which files were modified, what changes were made, whether tests pass.
7. BLOCKED/PENDING ITEMS: Deferred work, follow-ups, items waiting on external input.

Write the summary as if briefing a new engineer continuing this exact work. Be specific — file paths, function names, error messages, exact commands that worked.
INST

python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreCompact','additionalContext':sys.argv[1]}}))
" "$INSTRUCTIONS"
