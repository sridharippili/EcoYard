#!/bin/bash
# Shared helpers for EcoYard git hooks. Bash 3.2 compatible (macOS default).

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT" || exit 1

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; RST=$'\033[0m'
FAILED=0

fail() { echo "${RED}✗ $*${RST}" >&2; FAILED=1; }
warn() { echo "${YEL}! $*${RST}" >&2; }
ok()   { echo "${GRN}✓ $*${RST}"; }

# Staged files that still exist (added, copied, modified, renamed).
staged_files() { git diff --cached --name-only --diff-filter=ACMR; }
# All staged paths, including deletions.
staged_all() { git diff --cached --name-only; }

# Flutter ships its own dart. Find whichever is available.
find_dart() {
  if command -v dart >/dev/null 2>&1; then echo dart; return; fi
  if command -v flutter >/dev/null 2>&1; then echo "flutter --suppress-analytics pub"; return; fi
  echo ""
}

# A pubspec is a Flutter package if it depends on the flutter SDK.
is_flutter_pkg() { grep -Eq '^[[:space:]]+sdk:[[:space:]]*flutter' "$1/pubspec.yaml" 2>/dev/null; }

# Every directory in the repo that has a pubspec.yaml (excluding reference/ and build output).
dart_packages() {
  find . -name pubspec.yaml \
    -not -path './reference/*' -not -path '*/.dart_tool/*' -not -path '*/build/*' \
    -not -path '*/ios/*' -not -path '*/android/*' 2>/dev/null \
    | sed 's|/pubspec.yaml$||; s|^\./||'
}
