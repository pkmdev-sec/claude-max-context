# How to Install This (for Claude Code)

You're an agent setting up claude-max-context. Here's what to do, in order.

## Steps

0. **Clone** (if not already local) — `git clone https://github.com/pkmdev-sec/claude-max-context && cd claude-max-context`

1. **Preflight** — `bash lib/validate.sh`
   Stop if there are critical errors (missing jq or Claude Code CLI).

2. **Check profile** — `bash lib/tokens.sh`
   Shows which profile will be selected and why. Note it.

3. **Dry run** — `bash install.sh --dry-run`
   Should exit 0. If not, something's wrong with the config.

4. **Install** — `bash install.sh`
   Backs up existing config, detects profile, installs hooks + mesh + settings. Rolls back automatically if verification fails.

5. **Test** — `bash tests/run-all.sh`
   47 tests. All must pass.

6. **Report** — `bash lib/benchmark.sh`
   Show the user the results. It separates theoretical math from verified facts from unconfirmed claims. Don't present theoretical numbers as measurements.

7. **Tell the user** what got installed, where the backup is, and to open a new terminal (or `source ~/.zshrc`).

## Rules

- Don't skip the dry run.
- Don't hide test failures.
- The benchmark numbers are theoretical (config math), not live measurements. Say so.
- Everything goes in `~/.claude/`. Don't touch anything else.
- If install fails, it rolls back. Check the backup dir: `~/.claude/backups/`.
- To undo: `bash install.sh --uninstall`.
