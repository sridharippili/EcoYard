#!/bin/bash
# PreToolUse guard for Bash. Exit 2 = block; stderr is shown to Claude.
CMD="$(cat | jq -r '.tool_input.command // empty')"
[ -z "$CMD" ] && exit 0

block() { echo "BLOCKED by EcoYard guardrail: $1" >&2; exit 2; }
has() { echo "$CMD" | grep -Eq -- "$1"; }

# Skipping or disabling the git hooks
has '(^|[[:space:];&|])git[[:space:]].*--no-verify'               && block "--no-verify skips the quality gates. Fix the failure instead."
has 'git[[:space:]]+commit([[:space:]]+-[A-Za-z]*n|.*[[:space:]]-n([[:space:]]|$))' && block "'git commit -n' skips the hooks. Fix the failure instead."
has 'git[[:space:]]+config[^|;&]*core\.hooksPath'                 && block "Changing core.hooksPath disables the hooks."
has 'HUSKY=0|LEFTHOOK=0|SKIP=' && block "Disabling hooks via environment is not allowed."

# History-destroying git
has 'git[[:space:]]+push[^|;&]*(--force|[[:space:]]-f([[:space:]]|$)|--force-with-lease)' && block "Force-push requires the user to do it themselves."
has 'git[[:space:]]+reset[^|;&]*--hard'                           && block "git reset --hard discards work. Ask the user."
has 'git[[:space:]]+clean[^|;&]*-[A-Za-z]*f'                      && block "git clean -f deletes untracked files. Ask the user."
has 'git[[:space:]]+(checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)' && block "Discarding all working-tree changes. Ask the user."
has 'git[[:space:]]+branch[^|;&]*-D'                              && block "Force-deleting a branch. Ask the user."

# Broad deletes
has 'rm[[:space:]]+-[A-Za-z]*r[A-Za-z]*f?[[:space:]]+(/|~|\$HOME|\.|\*|\./\*)([[:space:]]|$)' && block "Recursive delete of a root/home/repo path."

# Writing to protected paths through the shell
PROT='(reference/|fixtures/|\.githooks/|scripts/hooks/|\.claude/hooks/|\.claude/settings\.json)'
has "(rm|mv|sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|tee|truncate|chmod|ln)[^|;&]*${PROT}" && block "Shell edits to protected paths (reference/, fixtures/, guardrail files) are not allowed."
has ">>?[[:space:]]*[^[:space:]]*${PROT}"                          && block "Redirecting output into a protected path is not allowed."
has "cp[[:space:]][^|;&]*[[:space:]][^[:space:]]*${PROT}[^[:space:]]*[[:space:]]*($|[;&|])" && block "Copying files INTO a protected path is not allowed."

# Reading secrets
has '(cat|less|more|head|tail|bat|grep)[^|;&]*(\.env([[:space:]]|$|\.)|\.pem|\.p8|\.p12|key\.properties)' && block "Don't read credential files into the conversation."

exit 0
