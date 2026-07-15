#!/usr/bin/env bash
# Static assertions over evaluate.yml — fail CI if trust-stage isolation regresses.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WF="$ROOT/.github/workflows/evaluate.yml"

if [[ ! -f "$WF" ]]; then
  echo "missing evaluate.yml" >&2
  exit 1
fi

# Three jobs must exist.
for job in prepare execute submit; do
  if ! grep -E "^  ${job}:" "$WF" >/dev/null; then
    echo "missing job: $job" >&2
    exit 1
  fi
done

# execute must not declare job-level secrets: block.
# Extract the execute job stanza (until submit:).
execute_block="$(awk '/^  execute:/{flag=1;next}/^  submit:/{flag=0}flag' "$WF")"

if printf '%s' "$execute_block" | grep -E '^[[:space:]]*secrets:' >/dev/null; then
  echo "execute job must not declare job-level secrets:" >&2
  exit 1
fi

# CALLBACK_SECRET must not appear under execute (only submit).
if printf '%s' "$execute_block" | grep -F 'CALLBACK_SECRET' >/dev/null; then
  echo "CALLBACK_SECRET must not appear in execute job" >&2
  exit 1
fi

if printf '%s' "$execute_block" | grep -F 'HIDDEN_TESTS_TOKEN' >/dev/null; then
  echo "HIDDEN_TESTS_TOKEN must not appear in execute job" >&2
  exit 1
fi

if printf '%s' "$execute_block" | grep -F 'WORKSPACE_READ_TOKEN' >/dev/null; then
  echo "WORKSPACE_READ_TOKEN must not appear in execute job" >&2
  exit 1
fi

# PREPARE_WRAP_SECRET may appear only on the decrypt step name/env — still under execute.
# Count occurrences: allowed in decrypt step only (env + optional comment). Soft-check: assert_execute_env.sh present.
if ! grep -F 'assert_execute_env.sh' "$WF" >/dev/null; then
  echo "execute must run assert_execute_env.sh after decrypt" >&2
  exit 1
fi

# submit must not checkout participant work via inputs participantRepo
submit_block="$(awk '/^  submit:/{flag=1;next}/^  [a-z]/{flag=0}flag' "$WF")"
if printf '%s' "$submit_block" | grep -F 'participantRepo' >/dev/null; then
  echo "submit must not reference participantRepo / checkout work" >&2
  exit 1
fi

if ! printf '%s' "$submit_block" | grep -F 'CALLBACK_SECRET' >/dev/null; then
  echo "submit must use CALLBACK_SECRET" >&2
  exit 1
fi

# Actions must be pinned by SHA (40 hex), not floating tags alone.
if grep -E 'uses: actions/[a-zA-Z0-9_-]+@v[0-9]' "$WF" >/dev/null; then
  echo "actions must be pinned by commit SHA, not @vN tags" >&2
  exit 1
fi

# No cache sharing across trust stages.
if grep -Ei 'actions/cache@|cache:' "$WF" >/dev/null; then
  echo "shared Actions cache is forbidden across prepare/execute/submit" >&2
  exit 1
fi

# Inputs must not include secret-like names.
if grep -Ei 'inputs:.*(token|secret|password|hmac)' "$WF" >/dev/null; then
  echo "workflow_dispatch inputs must remain non-secret" >&2
  exit 1
fi

echo "assert_workflow_isolation: ok"
