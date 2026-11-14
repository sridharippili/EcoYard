#!/bin/bash
# EcoYard pre-commit. Fast checks only (target: a few seconds).
# Slow checks (full test suite) live in pre-push.
source "$(dirname "$0")/common.sh"

FILES="$(staged_files)"
ALL="$(staged_all)"
[ -z "$ALL" ] && exit 0

# 1. Secrets ------------------------------------------------------------------
# Scan only lines being ADDED in this commit.
SECRET_RE='(hf_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|sk-[A-Za-z0-9_-]{32,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
GENERIC_RE='(api[_-]?key|secret|token|password|passwd)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{16,}["'"'"']'
HITS="$(git diff --cached -U0 --no-color -- . ':(exclude)docs/design/*' ':(exclude)scripts/hooks/*' ':(exclude).claude/hooks/*' \
  | grep -E '^\+[^+]' | grep -Ei -e "$SECRET_RE" -e "$GENERIC_RE" | cut -c1-120)"
if [ -n "$HITS" ]; then
  fail "Possible secret in staged changes. Move it to an untracked .env / --dart-define, never commit it:"
  echo "$HITS" | sed 's/^/    /' >&2
fi

echo "$FILES" | grep -Ei '(^|/)(\.env(\..*)?|.*\.pem|.*\.p12|.*\.p8|.*\.jks|.*\.keystore|key\.properties|.*\.mobileprovision)$' \
  | while read -r f; do [ -n "$f" ] && echo "$f"; done > /tmp/ecoyard_secret_files.$$
if [ -s /tmp/ecoyard_secret_files.$$ ]; then
  fail "Credential-type files must never be committed:"
  sed 's/^/    /' /tmp/ecoyard_secret_files.$$ >&2
fi
rm -f /tmp/ecoyard_secret_files.$$

# 2. Large files and model binaries ------------------------------------------
MAX_BYTES=$((5 * 1024 * 1024))
echo "$FILES" | while read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.tflite|*.mlmodel|*.mlpackage/*|*.onnx|*.pt|*.ckpt)
      echo "MODEL $f" ;;
  esac
  if [ -f "$f" ]; then
    size=$(wc -c < "$f" | tr -d ' ')
    [ "$size" -gt "$MAX_BYTES" ] && echo "LARGE $f ($((size / 1024 / 1024)) MB)"
  fi
done > /tmp/ecoyard_large.$$
if [ -s /tmp/ecoyard_large.$$ ]; then
  fail "Model binaries / files over 5 MB are not committed (models are downloaded at runtime):"
  sed 's/^/    /' /tmp/ecoyard_large.$$ >&2
fi
rm -f /tmp/ecoyard_large.$$

# 3. reference/ is read-only --------------------------------------------------
if echo "$ALL" | grep -q '^reference/'; then
  if [ "${ECOYARD_ALLOW_REFERENCE:-0}" = "1" ]; then
    warn "reference/ changes allowed by ECOYARD_ALLOW_REFERENCE=1"
  else
    fail "reference/ is read-only GardenEar source. Port from it; don't change it."
    echo "$ALL" | grep '^reference/' | head -5 | sed 's/^/    /' >&2
  fi
fi

# 4. ecoyard_core stays pure Dart --------------------------------------------
CORE=packages/ecoyard_core
if echo "$ALL" | grep -q "^$CORE/"; then
  if [ -f "$CORE/pubspec.yaml" ]; then
    # dependencies: block must be empty; no flutter SDK anywhere.
    deps="$(awk '/^dependencies:/{f=1;next} /^[^[:space:]#]/{f=0} f && /^[[:space:]]+[A-Za-z_]/' "$CORE/pubspec.yaml")"
    [ -n "$deps" ] && fail "$CORE must declare ZERO dependencies. Found:" && echo "$deps" | sed 's/^/    /' >&2
    grep -Eq 'sdk:[[:space:]]*flutter' "$CORE/pubspec.yaml" && fail "$CORE must not depend on the Flutter SDK"
  fi
  IMPORT_RE="^[[:space:]]*(import|export)[[:space:]]+['\"]"
  # lib/: only itself, and no platform-bound dart: libraries (core takes data in, does no I/O).
  # test/: may also use package:test and dart:io (to read fixtures/engine_cases.json).
  BAD_IMPORTS="$(echo "$FILES" | grep "^$CORE/.*\.dart$" | while read -r f; do
    case "$f" in
      ("$CORE"/test/*) allowed='package:(ecoyard_core|test)/'; banned='dart:(ui|html|ffi)' ;;
      (*)              allowed='package:ecoyard_core/';         banned='dart:(ui|io|html|ffi|isolate)' ;;
    esac
    grep -nE "${IMPORT_RE}package:" "$f" | grep -vE "$allowed" | sed "s|^|$f:|"
    grep -nE "${IMPORT_RE}${banned}['\"]" "$f" | sed "s|^|$f:|"
  done)"
  if [ -n "$BAD_IMPORTS" ]; then
    fail "$CORE must stay pure Dart (no Flutter, no plugins, no I/O in lib/):"
    echo "$BAD_IMPORTS" | sed 's/^/    /' >&2
  fi
fi

# 5. Dart format + analyze on staged Dart files ------------------------------
DART_FILES="$(echo "$FILES" | grep '\.dart$' | grep -v '^reference/' | grep -vE '\.(g|freezed|mocks)\.dart$')"
if [ -n "$DART_FILES" ]; then
  if ! command -v dart >/dev/null 2>&1; then
    fail "Dart files staged but 'dart' is not on PATH. Install Flutter (see docs/STATE.md) — checks are never skipped silently."
  else
    # shellcheck disable=SC2086
    if ! dart format --output=none --set-exit-if-changed $DART_FILES >/tmp/ecoyard_fmt.$$ 2>&1; then
      fail "Unformatted Dart. Run: dart format $(echo $DART_FILES | tr '\n' ' ')"
      grep -i 'changed' /tmp/ecoyard_fmt.$$ | sed 's/^/    /' >&2
    fi
    # shellcheck disable=SC2086
    if ! dart analyze --fatal-warnings $DART_FILES >/tmp/ecoyard_an.$$ 2>&1; then
      fail "dart analyze found problems:"
      grep -E '(error|warning|info) -' /tmp/ecoyard_an.$$ | head -20 | sed 's/^/    /' >&2
    fi
    rm -f /tmp/ecoyard_fmt.$$ /tmp/ecoyard_an.$$
  fi
fi

# 6. Content JSON -------------------------------------------------------------
if echo "$ALL" | grep -qE '^(content/|fixtures/)'; then
  for j in $(echo "$FILES" | grep -E '^(content|fixtures)/.*\.json$'); do
    python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$j" 2>/dev/null || fail "Invalid JSON: $j"
  done
  if echo "$ALL" | grep -q '^content/'; then
    if [ -f scripts/validate_content.dart ]; then
      if command -v dart >/dev/null 2>&1; then
        dart run scripts/validate_content.dart || fail "validate_content failed"
      else
        fail "content/ changed but 'dart' is not on PATH, so it can't be validated."
      fi
    else
      fail "content/ changed but scripts/validate_content.dart does not exist yet. Write the validator first (PLAN.md §4.4)."
    fi
  fi
fi

# 7. Privacy copy that must never ship ---------------------------------------
BAD_COPY="$(echo "$FILES" | grep -E '^(app|packages)/.*\.(dart|arb|json)$' | xargs grep -HnE 'Recording deleted|Processed on your phone, then deleted' 2>/dev/null)"
if [ -n "$BAD_COPY" ]; then
  fail "False privacy copy (audio goes online via NatureLM — badge must be provider-aware, PLAN.md §0.1):"
  echo "$BAD_COPY" | sed 's/^/    /' >&2
fi

if [ "$FAILED" -ne 0 ]; then
  echo "${RED}pre-commit failed. Fix the above. Do not use --no-verify.${RST}" >&2
  exit 1
fi
ok "pre-commit checks passed"
