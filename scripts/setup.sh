#!/bin/bash
# One-time setup after cloning. Points git at the repo's hooks.
set -e
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x .githooks/* scripts/hooks/*.sh scripts/*.sh .claude/hooks/*.sh 2>/dev/null || true
echo "Git hooks enabled (.githooks/)."
command -v dart >/dev/null || echo "Note: Flutter/Dart not on PATH yet — Dart checks will fail until it is."
