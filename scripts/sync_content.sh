#!/usr/bin/env bash
# Copies content/*.json into app/assets/content/ so Flutter can bundle it
# (assets cannot live outside the app folder). content/ is the only place to
# edit; app/test/bundled_content_test.dart fails when the copies drift.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/app/assets/content"
cp "$root"/content/*.json "$root/app/assets/content/"
echo "Synced $(ls "$root"/content/*.json | wc -l | tr -d ' ') content files into app/assets/content/"
