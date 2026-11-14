#!/bin/bash
# EcoYard commit-msg: readable subject, and deliberate fixture changes.
source "$(dirname "$0")/common.sh"
MSG_FILE="$1"

SUBJECT="$(grep -v '^#' "$MSG_FILE" | sed '/^[[:space:]]*$/d' | head -1)"
[ -z "$SUBJECT" ] && fail "Empty commit message."
[ "${#SUBJECT}" -gt 72 ] && fail "Subject is ${#SUBJECT} chars; keep it ≤ 72."
echo "$SUBJECT" | grep -qiE '^(wip|fix|update|changes|stuff|misc)\.?$' && fail "Subject '$SUBJECT' says nothing. Describe the change."

# fixtures/engine_cases.json defines correct behaviour. Changing it must be a
# conscious decision, marked in the message, never a way to make a test pass.
if git diff --cached --name-only | grep -q '^fixtures/'; then
  grep -q '\[fixtures\]' "$MSG_FILE" || fail "fixtures/ changed. Add '[fixtures]' to the message and say WHY the expected behaviour changed."
fi

[ "$FAILED" -ne 0 ] && exit 1
exit 0
