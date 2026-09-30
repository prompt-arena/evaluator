#!/usr/bin/env bash
# Orchestrate evaluation and emit the canonical `components` JSON the backend expects.
# 🔴 Must run WITHOUT the hidden-tests token in its environment (it executes participant code).
# Hidden tests, if any, must already be staged at <work>/tests/hidden by fetch_hidden.sh.
#
# <defect_config> is optional and defaults to the path prepare stages it at. It is answer-key
# material from the challenge's private hidden repository; an absent file simply means no defect
# detection for this challenge.
#
# Usage: run.sh <participant_work_dir> <manifest.json> [defect_config.json]
set -uo pipefail

WORK="$1"
MANIFEST="$2"
DEFECT_CONFIG="${3:-hidden_defects.json}"
DIR="$(cd "$(dirname "$0")" && pwd)"

INTEG="$("$DIR/verify_integrity.sh" "$MANIFEST" "$WORK")"
intact="$(printf '%s' "$INTEG" | jq -r '.protectedFilesIntact')"

if [[ "$intact" != "true" ]]; then
  # Tampered protected files: do not run the (possibly altered) tests. Zero everything → backend scores 0.
  # No `defects` group either: nothing ran, so nothing was assessed. The backend reads an absent group
  # as "not assessed" rather than as "nothing was planted", and fails the defect check accordingly.
  jq -n --argjson integrity "$INTEG" \
    '{integrity:$integrity, build:{ok:false}, tests:{public:{passed:0,total:0}, hidden:{passed:0,total:0}}, quality:{lintIssues:0, securityFlags:0}}'
  exit 0
fi

HIDDEN_REPORT="$(mktemp)"
trap 'rm -f "$HIDDEN_REPORT"' EXIT

BUILD="$("$DIR/build.sh" "$WORK")"
PUBLIC="$("$DIR/run_public_tests.sh" "$WORK")"
HIDDEN="$("$DIR/run_hidden_tests.sh" "$WORK" "$HIDDEN_REPORT")"
QUALITY="$("$DIR/quality.sh" "$WORK")"

# Additive and optional: empty for every challenge with no defect config staged from its private
# hidden repository, which keeps the components object byte-identical to the legacy shape for those
# challenges. The config is answer-key material and never lives in this public repo.
DEFECTS="$("$DIR/detect_defects.sh" "$DEFECT_CONFIG" "$HIDDEN_REPORT")"

jq -n \
  --argjson integrity "$INTEG" \
  --argjson build "$BUILD" \
  --argjson public "$PUBLIC" \
  --argjson hidden "$HIDDEN" \
  --argjson quality "$QUALITY" \
  --argjson defects "${DEFECTS:-null}" \
  '{integrity:$integrity, build:$build, tests:{public:$public, hidden:$hidden}, quality:$quality}
   + (if $defects == null then {} else {defects:$defects} end)'
