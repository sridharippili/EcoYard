#!/bin/bash
# PreToolUse guard for Edit / Write / MultiEdit / NotebookEdit.
# Exit 2 = block the tool call; stderr is shown to Claude.
INPUT="$(cat)"
FILE="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$FILE" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
REL="${FILE#"$ROOT"/}"

block() { echo "BLOCKED by EcoYard guardrail: $1" >&2; exit 2; }

case "$REL" in
  reference/*)
    block "reference/ is read-only GardenEar source. Read it and port from it; never edit it." ;;
  fixtures/engine_cases.json|fixtures/*)
    block "fixtures/ defines correct behaviour and is changed only by the user, deliberately. If you believe an expected value is wrong, STOP and explain why to the user instead of editing it." ;;
  .githooks/*|scripts/hooks/*|.claude/hooks/*|.claude/settings.json|.github/workflows/*)
    block "Guardrail files ($REL) are not edited by agents. Describe the change you want and let the user make or approve it." ;;
  .env|.env.*|*/.env|*/.env.*|*.pem|*.p12|*.p8|*.jks|*.keystore|*key.properties)
    block "Credential files are never written by agents." ;;
esac
exit 0
