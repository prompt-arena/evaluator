#!/usr/bin/env bash
# Orchestrate evaluation and emit the canonical `components` JSON the backend expects.
# 🔴 Must run WITHOUT the hidden-tests token in its environment (it executes participant code).
# Hidden tests, if any, must already be staged at <work>/tests/hidden by fetch_hidden.sh.
#
# Usage: run.sh <participant_work_dir> <manifest.json>
set -uo pipefail

WORK="$1"
MANIFEST="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"

INTEG="$("$DIR/verify_integrity.sh" "$MANIFEST" "$WORK")"
intact="$(printf '%s' "$INTEG" | jq -r '.protectedFilesIntact')"

if [[ "$intact" != "true" ]]; then
  # Tampered protected files: do not run the (possibly altered) tests. Zero everything → backend scores 0.
  jq -n --argjson integrity "$INTEG" \
    '{integrity:$integrity, build:{ok:false}, tests:{public:{passed:0,total:0}, hidden:{passed:0,total:0}}, quality:{lintIssues:0, securityFlags:0}}'
  exit 0
fi

BUILD="$("$DIR/build.sh" "$WORK")"
PUBLIC="$("$DIR/run_public_tests.sh" "$WORK")"
HIDDEN="$("$DIR/run_hidden_tests.sh" "$WORK")"
QUALITY="$("$DIR/quality.sh" "$WORK")"

jq -n \
  --argjson integrity "$INTEG" \
  --argjson build "$BUILD" \
  --argjson public "$PUBLIC" \
  --argjson hidden "$HIDDEN" \
  --argjson quality "$QUALITY" \
  '{integrity:$integrity, build:$build, tests:{public:$public, hidden:$hidden}, quality:$quality}'
