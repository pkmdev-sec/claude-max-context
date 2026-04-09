# claude-max-context repo

This is a context optimization toolkit for Claude Code. If you're working on the code itself (not installing it), here's what matters.

## Structure
- `lib/` — core logic: platform detection, token fallback, benchmark math
- `hooks/` — Claude Code lifecycle hooks (session-start, pre-compact, etc.)
- `mesh/` — filesystem-based IPC between parallel Claude sessions
- `config/` — settings template + three profiles (1m, 200k, conservative)
- `tests/` — 47-test verification suite, run with `bash tests/run-all.sh`
- `install.sh` — global installer with backup + rollback

## Conventions
- All scripts use `set -euo pipefail`
- Hooks read JSON from stdin, write JSON to stdout
- `_lib.sh` provides `_json()` for zero-overhead field extraction (~0.01ms)
- Profiles define: context_window, compact_pct, output_tokens, blocking_limit, model
- The benchmark separates theoretical/verified/observable claims — keep it that way

## Testing
Run `bash tests/run-all.sh` after any change. It checks syntax, profile JSON, fallback logic, benchmark math, hook I/O contracts, template rendering, and installer dry-run.

## Key rule
Don't claim anything we can't prove. If a number comes from config math, label it theoretical. If it needs a live session to confirm, put it in the "observable" section.
