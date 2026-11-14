#!/bin/bash
# EcoYard pre-push: full analyze + test of every Dart/Flutter package.
source "$(dirname "$0")/common.sh"

PKGS="$(dart_packages)"
if [ -z "$PKGS" ]; then
  ok "pre-push: no Dart packages yet, nothing to test"
  exit 0
fi
if ! command -v dart >/dev/null 2>&1; then
  fail "Dart packages exist but 'dart' is not on PATH. Install Flutter (see docs/STATE.md)."
  exit 1
fi

for p in $PKGS; do
  echo "── $p"
  if is_flutter_pkg "$p"; then
    (cd "$p" && flutter analyze --fatal-warnings) || fail "$p: flutter analyze"
    if [ -d "$p/test" ]; then (cd "$p" && flutter test) || fail "$p: flutter test"; fi
  else
    (cd "$p" && dart analyze --fatal-warnings) || fail "$p: dart analyze"
    if [ -d "$p/test" ]; then (cd "$p" && dart test) || fail "$p: dart test"; fi
  fi
done

if [ -f scripts/validate_content.dart ]; then
  dart run scripts/validate_content.dart || fail "validate_content"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "${RED}pre-push failed. Nothing was pushed.${RST}" >&2
  exit 1
fi
ok "pre-push: all packages analyze and test clean"
