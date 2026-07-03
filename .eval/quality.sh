#!/usr/bin/env bash
# Lightweight quality + security signal on the participant's edited source. Emits counts JSON.
# V1 heuristics (deterministic, no external services):
#   - lintIssues: TypeScript strict diagnostics count (tsc already gates build; here we count warnings-ish).
#   - securityFlags: naive scan for risky patterns in src/ (eval, child_process, disabled TLS, hardcoded secrets).
# Usage: quality.sh <participant_work_dir>
set -uo pipefail

WORK="$1"
cd "$WORK"

# Security scan over participant-editable source only.
security_flags=0
if [[ -d src ]]; then
  security_flags="$(grep -rInE "eval\(|child_process|exec\(|rejectUnauthorized\s*[:=]\s*false|process\.env\.[A-Z_]*SECRET|AKIA[0-9A-Z]{16}" src 2>/dev/null | wc -l | tr -d ' ')"
fi

# Lint signal: count TS diagnostics (0 when clean; build.sh already enforces a clean compile).
lint_issues="$(npx tsc --noEmit 2>&1 | grep -cE "error TS" || true)"

jq -n --argjson lintIssues "${lint_issues:-0}" --argjson securityFlags "${security_flags:-0}" \
  '{lintIssues: $lintIssues, securityFlags: $securityFlags}'
