{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "{{MODEL}}",
  "alwaysThinkingEnabled": true,
  "effortLevel": "high",
  "env": {
{{ENV_BLOCK}}
  },
  "hooks": {
    "SessionStart": [{"hooks": [{"command": "bash $HOME/.claude/hooks/session-start.sh", "timeout": 30, "type": "command"}]}],
    "PreToolUse": [{"hooks": [{"command": "bash $HOME/.claude/hooks/pre-tool-use.sh", "timeout": 30, "type": "command"}]}],
    "PostToolUse": [{"hooks": [{"command": "bash $HOME/.claude/hooks/post-tool-stale.sh", "timeout": 3, "type": "command"}]}],
    "PreCompact": [{"hooks": [{"command": "bash $HOME/.claude/hooks/pre-compact.sh", "timeout": 5, "type": "command"}]}],
    "Stop": [{"hooks": [{"command": "bash $HOME/.claude/hooks/stop-handoff.sh", "timeout": 15, "type": "command"}]}],
    "SessionEnd": [{"hooks": [{"command": "bash $HOME/.claude/mesh/hooks/mesh-stop.sh", "timeout": 5, "type": "command"}]}]
  },
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)", "Glob(*)", "Grep(*)", "Agent(*)", "WebSearch", "WebFetch"],
    "defaultMode": "bypassPermissions"
  },
  "autoCompactEnabled": true,
  "includeGitInstructions": true,
  "skipDangerousModePermissionPrompt": true,
  "showThinkingSummaries": false
}
