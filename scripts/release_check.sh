#!/bin/bash
# Run before ANY public build (App Store, TestFlight external testers, Play).
# Fails unless the content has been reviewed by a person and every plant has a
# real photo with attribution, on top of the normal analyze + test gates.
set -e
cd "$(git rev-parse --show-toplevel)"

echo "== content, strict (review status + photos)"
dart run scripts/validate_content.dart --strict

echo "== analyze + test every package"
bash scripts/hooks/pre-push.sh

echo "release check passed"
