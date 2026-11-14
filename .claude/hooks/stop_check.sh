#!/bin/bash
# Stop hook: before Claude finishes a turn, if Dart code changed, run the tests
# of the affected packages. On failure, block the stop (exit 2) and hand the
# failure back so it gets fixed. Runs once per turn (stop_hook_active guard).
INPUT="$(cat)"
[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$ROOT" || exit 0
command -v dart >/dev/null 2>&1 || exit 0

CHANGED="$(git status --porcelain --untracked-files=all | awk '{print $NF}' | grep -E '\.dart$|pubspec\.yaml$' | grep -v '^reference/')"
[ -z "$CHANGED" ] && exit 0

# Map changed files to their package (nearest dir with pubspec.yaml).
PKGS=""
for f in $CHANGED; do
  d="$(dirname "$f")"
  while [ "$d" != "." ] && [ ! -f "$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done
  [ -f "$d/pubspec.yaml" ] && PKGS="$PKGS
$d"
done
PKGS="$(echo "$PKGS" | sed '/^$/d' | sort -u)"
[ -z "$PKGS" ] && exit 0

FAILS=""
for p in $PKGS; do
  [ -d "$p/test" ] || continue
  if grep -Eq 'sdk:[[:space:]]*flutter' "$p/pubspec.yaml"; then
    OUT="$(cd "$p" && flutter test 2>&1)"
  else
    OUT="$(cd "$p" && dart test 2>&1)"
  fi
  [ $? -ne 0 ] && FAILS="$FAILS
── $p
$(echo "$OUT" | tail -25)"
done

if [ -n "$FAILS" ]; then
  echo "Tests are failing in packages you changed. Reproduce, pinpoint the exact method/class, and fix only that (see CLAUDE.md 'Bug-fix protocol'). If a failing test is an intentional reproduction awaiting a fix, say so to the user.$FAILS" >&2
  exit 2
fi
exit 0
