#!/usr/bin/env bash
# Map the challenge's planted defects onto the hidden tests that actually ran (§9.5, implicit detection).
#
# A defect is DETECTED when every hidden test designated for it passed. That is the stronger of the
# two routes in the frozen model: the participant cannot satisfy it by announcing that they found
# something, only by shipping work in which the underlying flaw is genuinely gone.
#
# 🔴 The defect configuration is ANSWER-KEY MATERIAL and lives in the challenge's PRIVATE hidden-tests
# repository, never in this public repo. It reaches us the same way the hidden tests do: fetched in
# `prepare` with the App installation token and carried in the encrypted prepare artifact. This repo
# holds only the generic engine. An absent config means "no defect detection for this challenge" and
# produces no output at all, which the backend reads as a challenge with nothing planted.
#
# Emits nothing (exit 0, empty output) when there is no config or it declares no defects — a challenge
# without defects must evaluate exactly as it did before this step existed.
#
# 🔴 Reports evidence only. Which defects exist, whether the verdict passes, what capability this
# demonstrates, and even how many defects were planted are all decided by the backend against the
# challenge version's immutable evaluation profile. This script cannot assert any of them.
#
# Usage: detect_defects.sh <defect_config.json> <hidden_jest_report.json>
set -uo pipefail

CONFIG="${1:-}"
REPORT="${2:-}"

# No private config staged → nothing to assess. Silence is the legacy shape.
if [[ -z "$CONFIG" || ! -s "$CONFIG" ]]; then
  exit 0
fi

# A config that exists but does not parse is a broken hidden repository, not an empty one. Refuse to
# report "nothing planted" for it: emit nothing so the backend's absent-group path fails closed.
if ! jq -e 'type == "object" and (.defects | type == "array")' "$CONFIG" >/dev/null 2>&1; then
  echo "detect_defects: defect config is present but malformed; reporting no evidence" >&2
  exit 0
fi

if ! jq -e '.defects | length > 0' "$CONFIG" >/dev/null 2>&1; then
  exit 0
fi

# Every assertion jest reported as passing, by its fully qualified name.
if [[ -n "$REPORT" && -s "$REPORT" ]]; then
  PASSED_NAMES="$(jq -c '[.testResults[]?.assertionResults[]? | select(.status == "passed") | .fullName]' \
    "$REPORT" 2>/dev/null || echo '[]')"
else
  PASSED_NAMES='[]'
fi

# A designated test that the suite never reported is a config that has drifted from the hidden tests
# beside it — usually someone renaming a test. The defect then becomes undetectable and every
# submission fails it, so say so in the run log. This is a warning rather than an error because a
# broken config must not be able to stop evaluations; the detection rate falling to zero is the
# signal that is meant to catch it, and this line is what explains the zero when someone looks.
if [[ -n "$REPORT" && -s "$REPORT" ]]; then
  jq -r --slurpfile config "$CONFIG" '
    [.testResults[]?.assertionResults[]?.fullName] as $seen
    | $config[0].defects[]
    | .id as $id
    | (.detection.testNames // [])[]
    | select(. as $name | ($seen | index($name)) == null)
    | "warning: defect \($id) designates a test the hidden suite did not report: \(.)"
  ' "$REPORT" >&2 2>/dev/null || true
fi

# A defect with no designated tests is never reported as detected: an empty conjunction is vacuously
# true, and "we checked nothing, so you must have handled it" is the one answer this must not give.
jq -n \
  --slurpfile config "$CONFIG" \
  --argjson passed "$PASSED_NAMES" \
  '
  ($config[0].defects) as $defects
  | ($passed | map({key: ., value: true}) | from_entries) as $ok
  | [ $defects[]
      | select((.detection.testNames // []) | length > 0)
      | select([ .detection.testNames[] | $ok[.] // false ] | all)
      | .id ] as $detected
  | { planted: ($defects | length), detected: ($detected | length), detectedIds: $detected }
  '
