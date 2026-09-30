#!/usr/bin/env bash
# Tests for detect_defects.sh.
#
# The cases that matter are the ones where being wrong is silent: a challenge with no defect config
# that must keep behaving exactly as it did, and a defect that must never be reported as handled when
# nothing actually demonstrated it. Both would ship happily and be wrong for months.
#
# 🔴 Every fixture here is synthetic. Real defect ids and real hidden-test names are answer-key
# material and must never appear in this public repository — see assert_no_answer_key.sh.
#
# Usage: .eval/detect_defects.test.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/detect_defects.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0

expect() {
  local name="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$name" "$want" "$got"
    FAILURES=$((FAILURES + 1))
  fi
}

config() {
  local path="$WORK/defects.json"
  printf '%s' "$1" >"$path"
  printf '%s' "$path"
}

# A jest --json report in which the named tests passed and one unrelated test failed.
report() {
  local path="$WORK/report.json"
  local names=("$@")
  {
    printf '{"testResults":[{"assertionResults":['
    local first=1
    for n in "${names[@]}"; do
      [[ $first -eq 0 ]] && printf ','
      printf '{"status":"passed","fullName":"%s"}' "$n"
      first=0
    done
    [[ $first -eq 0 ]] && printf ','
    printf '{"status":"failed","fullName":"synthetic unrelated test"}'
    printf ']}]}'
  } >"$path"
  printf '%s' "$path"
}

ONE_DEFECT='{
  "schemaVersion": 1,
  "defects": [
    { "id": "test_defect_alpha",
      "detection": { "method": "hiddenTests", "testNames": ["synthetic test one", "synthetic test two"] } }
  ]
}'

TWO_DEFECTS='{
  "schemaVersion": 1,
  "defects": [
    { "id": "test_defect_alpha",
      "detection": { "method": "hiddenTests", "testNames": ["synthetic test one"] } },
    { "id": "test_defect_beta",
      "detection": { "method": "hiddenTests", "testNames": ["synthetic test two"] } }
  ]
}'

# --- a challenge with no defect config behaves exactly as it did before this step existed ---

out="$("$SUT" "" "$(report "synthetic test one")")"
expect "no config argument emits nothing" "" "$out"

out="$("$SUT" "$WORK/never-staged.json" "$(report "synthetic test one")")"
expect "an unstaged config emits nothing" "" "$out"

out="$("$SUT" "$(config '{"schemaVersion":1,"defects":[]}')" "$(report "synthetic test one")")"
expect "empty defects array emits nothing" "" "$out"

# A config that exists but is broken must not read as "nothing was planted". Emitting nothing sends
# the backend down its absent-group path, which fails the defect check closed.
out="$("$SUT" "$(config 'not json at all')" "$(report "synthetic test one")" 2>/dev/null)"
expect "a malformed config emits nothing rather than zero defects" "" "$out"

out="$("$SUT" "$(config '{"schemaVersion":1}')" "$(report "synthetic test one")" 2>/dev/null)"
expect "a config missing its defects array emits nothing" "" "$out"

# --- detection requires every designated test to pass ---

out="$("$SUT" "$(config "$ONE_DEFECT")" "$(report "synthetic test one" "synthetic test two")" | jq -c .)"
expect "all designated tests passing detects the defect" \
  '{"planted":1,"detected":1,"detectedIds":["test_defect_alpha"]}' "$out"

out="$("$SUT" "$(config "$ONE_DEFECT")" "$(report "synthetic test one")" | jq -c .)"
expect "a partially handled defect is not detected" \
  '{"planted":1,"detected":0,"detectedIds":[]}' "$out"

out="$("$SUT" "$(config "$ONE_DEFECT")" "$(report "synthetic unrelated")" | jq -c .)"
expect "no designated test passing detects nothing" \
  '{"planted":1,"detected":0,"detectedIds":[]}' "$out"

out="$("$SUT" "$(config "$TWO_DEFECTS")" "$(report "synthetic test two")" | jq -c .)"
expect "defects are detected independently" \
  '{"planted":2,"detected":1,"detectedIds":["test_defect_beta"]}' "$out"

out="$("$SUT" "$(config "$TWO_DEFECTS")" "$(report "synthetic test one" "synthetic test two")" | jq -c .)"
expect "a full sweep reports both" \
  '{"planted":2,"detected":2,"detectedIds":["test_defect_alpha","test_defect_beta"]}' "$out"

# --- the failure modes that must not read as success ---

# A hidden suite that never ran produces no passing tests, which is not the same as a clean run.
out="$("$SUT" "$(config "$ONE_DEFECT")" "$WORK/does-not-exist.json" | jq -c .)"
expect "a missing report detects nothing" \
  '{"planted":1,"detected":0,"detectedIds":[]}' "$out"

printf '%s' '' >"$WORK/empty.json"
out="$("$SUT" "$(config "$ONE_DEFECT")" "$WORK/empty.json" | jq -c .)"
expect "an empty report detects nothing" \
  '{"planted":1,"detected":0,"detectedIds":[]}' "$out"

out="$("$SUT" "$(config "$ONE_DEFECT")" | jq -c .)"
expect "a missing report argument detects nothing" \
  '{"planted":1,"detected":0,"detectedIds":[]}' "$out"

# An empty conjunction is vacuously true, so a defect nobody wired up to a test would otherwise be
# reported as handled by every submission — the worst possible default for a detection mechanism.
NO_TESTS='{"schemaVersion":1,"defects":[{"id":"test_defect_alpha","detection":{"method":"hiddenTests","testNames":[]}}]}'
out="$("$SUT" "$(config "$NO_TESTS")" "$(report "synthetic test one")" | jq -c .)"
expect "a defect with no designated tests is never detected" \
  '{"planted":1,"detected":0,"detectedIds":[]}' "$out"

# The planted count still comes from the config even when nothing is detectable, so the backend
# cross-check sees the real denominator rather than a silently shrunk one.
expect "the planted count is the declared count" "1" \
  "$("$SUT" "$(config "$NO_TESTS")" "$(report "synthetic test one")" | jq -r .planted)"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$FAILURES"
  exit 1
fi

printf '\nall tests passed\n'
