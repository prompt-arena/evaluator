#!/usr/bin/env bash
# Run the HIDDEN tests that were already staged into <work>/tests/hidden by fetch_hidden.sh.
# 🔴 Runs participant code, so it must NOT have the hidden-tests token in its environment.
# Emits {passed,total} JSON. If no hidden tests are staged, returns zeros.
# Usage: run_hidden_tests.sh <participant_work_dir>
set -uo pipefail

WORK="$1"

if [[ ! -d "$WORK/tests/hidden" ]]; then
  jq -n '{passed: 0, total: 0}'
  exit 0
fi

cd "$WORK"
out="$(npx jest --ci --json --testMatch '**/tests/hidden/**/*.test.ts' 2>/dev/null || true)"
summary="$(printf '%s' "$out" | tail -n 1)"

passed="$(printf '%s' "$summary" | jq -r '.numPassedTests // 0' 2>/dev/null || echo 0)"
total="$(printf '%s' "$summary" | jq -r '.numTotalTests // 0' 2>/dev/null || echo 0)"

jq -n --argjson passed "${passed:-0}" --argjson total "${total:-0}" \
  '{passed: $passed, total: $total}'
