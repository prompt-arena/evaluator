#!/usr/bin/env bash
# Run the participant's PUBLIC tests. Emits {passed,total} JSON from Jest's JSON reporter.
# Usage: run_public_tests.sh <participant_work_dir>
set -uo pipefail

WORK="$1"
cd "$WORK"

out="$(npx jest --ci --json --testMatch '**/tests/public/**/*.test.ts' 2>/dev/null || true)"
# Grab the last line that is valid JSON (Jest prints the summary object last).
summary="$(printf '%s' "$out" | tail -n 1)"

passed="$(printf '%s' "$summary" | jq -r '.numPassedTests // 0' 2>/dev/null || echo 0)"
total="$(printf '%s' "$summary" | jq -r '.numTotalTests // 0' 2>/dev/null || echo 0)"

jq -n --argjson passed "${passed:-0}" --argjson total "${total:-0}" \
  '{passed: $passed, total: $total}'
