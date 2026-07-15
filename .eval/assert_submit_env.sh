#!/usr/bin/env bash
# Fail the submit job if App credentials / installation tokens / wrap secret / fetch PATs appear.
# submit may only use CALLBACK_SECRET + BACKEND_URL (+ result artifact). Never App mint or workspace/hidden fetch.
set -euo pipefail

leaked=0
for v in \
  PREPARE_WRAP_SECRET \
  EVALUATOR_APP_PRIVATE_KEY \
  EVALUATOR_APP_CLIENT_ID \
  HIDDEN_INSTALLATION_TOKEN \
  WORKSPACE_INSTALLATION_TOKEN \
  HIDDEN_TESTS_TOKEN \
  WORKSPACE_READ_TOKEN \
  APP_PRIVATE_KEY \
  GITHUB_APP_PRIVATE_KEY
do
  if [[ -n "${!v:-}" ]]; then
    echo "assert_submit_env: $v is set (forbidden in submit)" >&2
    leaked=1
  fi
done

if [[ "$leaked" -ne 0 ]]; then
  exit 1
fi

echo "assert_submit_env: ok"
