#!/usr/bin/env bash
# Fail the execute job if evaluator secrets appear in the environment (defense in depth).
# PREPARE_WRAP_SECRET must only exist on the decrypt step; CALLBACK / tokens must never appear here.
set -euo pipefail

leaked=0
for v in CALLBACK_SECRET HIDDEN_TESTS_TOKEN WORKSPACE_READ_TOKEN BACKEND_URL PREPARE_WRAP_SECRET; do
  if [[ -n "${!v:-}" ]]; then
    echo "assert_execute_env: $v is set (forbidden in evaluate steps)" >&2
    leaked=1
  fi
done

if [[ "$leaked" -ne 0 ]]; then
  exit 1
fi

echo "assert_execute_env: ok"
