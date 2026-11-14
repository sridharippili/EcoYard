#!/bin/bash
# PostToolUse after Edit/Write: analyze the edited Dart file immediately and
# feed any error straight back to Claude (exit 2), so mistakes are fixed while
# the context is fresh.
FILE="$(cat | jq -r '.tool_input.file_path // empty')"
case "$FILE" in *.dart) ;; *) exit 0 ;; esac
[ -f "$FILE" ] || exit 0
command -v dart >/dev/null 2>&1 || exit 0

OUT="$(dart analyze --fatal-warnings "$FILE" 2>&1)"
if [ $? -ne 0 ]; then
  echo "dart analyze reports problems in $FILE — fix them now, touching only the code involved:" >&2
  echo "$OUT" | grep -E '(error|warning) -' | head -15 >&2
  exit 2
fi
exit 0
