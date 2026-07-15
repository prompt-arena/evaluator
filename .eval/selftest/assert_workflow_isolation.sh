#!/usr/bin/env bash
# Static assertions over evaluate.yml — fail CI if trust-stage isolation or App-mint auth regresses.
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

prepare_block="$(awk '/^  prepare:/{flag=1;next}/^  execute:/{flag=0}flag' "$WF")"
execute_block="$(awk '/^  execute:/{flag=1;next}/^  submit:/{flag=0}flag' "$WF")"
submit_block="$(awk '/^  submit:/{flag=1;next}/^  [a-z]/{flag=0}flag' "$WF")"

# --- Obsolete long-lived PATs must be gone from live wiring ---
if grep -E 'secrets\.(WORKSPACE_READ_TOKEN|HIDDEN_TESTS_TOKEN)' "$WF" >/dev/null; then
  echo "secrets.WORKSPACE_READ_TOKEN / secrets.HIDDEN_TESTS_TOKEN must not be wired in evaluate.yml" >&2
  exit 1
fi
if grep -E 'token: \$\{\{ secrets\.(WORKSPACE_READ_TOKEN|HIDDEN_TESTS_TOKEN)' "$WF" >/dev/null; then
  echo "checkout must not use PAT secrets for token:" >&2
  exit 1
fi

# --- prepare: App mint + persist-credentials: false ---
if ! printf '%s' "$prepare_block" | grep -F 'actions/create-github-app-token@' >/dev/null; then
  echo "prepare must mint tokens via SHA-pinned actions/create-github-app-token" >&2
  exit 1
fi
# Exactly two mint steps (workspace + hidden), both SHA-pinned (40 hex after @).
mint_count="$(printf '%s' "$prepare_block" | grep -cE 'uses: actions/create-github-app-token@[0-9a-f]{40}' || true)"
if [[ "$mint_count" -lt 2 ]]; then
  echo "prepare must SHA-pin create-github-app-token at least twice (workspace + hidden)" >&2
  exit 1
fi
if ! printf '%s' "$prepare_block" | grep -F 'persist-credentials: false' >/dev/null; then
  echo "workspace checkout must set persist-credentials: false" >&2
  exit 1
fi
if ! printf '%s' "$prepare_block" | grep -F 'owner: promptarena-workspaces' >/dev/null; then
  echo "prepare must mint workspace token for owner promptarena-workspaces" >&2
  exit 1
fi
if ! printf '%s' "$prepare_block" | grep -F 'owner: prompt-arena' >/dev/null; then
  echo "prepare must mint hidden token for owner prompt-arena" >&2
  exit 1
fi
if ! printf '%s' "$prepare_block" | grep -F 'HIDDEN_INSTALLATION_TOKEN' >/dev/null; then
  echo "prepare must pass HIDDEN_INSTALLATION_TOKEN into prepare.sh only" >&2
  exit 1
fi
if ! printf '%s' "$prepare_block" | grep -F 'EVALUATOR_APP_PRIVATE_KEY' >/dev/null; then
  echo "prepare must reference secrets.EVALUATOR_APP_PRIVATE_KEY" >&2
  exit 1
fi
if ! printf '%s' "$prepare_block" | grep -F 'EVALUATOR_APP_CLIENT_ID' >/dev/null; then
  echo "prepare must reference vars.EVALUATOR_APP_CLIENT_ID" >&2
  exit 1
fi
# Installation tokens must be step outputs — not repository secrets named *_TOKEN for GitHub fetch.
if printf '%s' "$prepare_block" | grep -E 'secrets\.(WORKSPACE|HIDDEN)_' >/dev/null; then
  echo "prepare must not use long-lived secrets.*_TOKEN for GitHub fetch" >&2
  exit 1
fi

# --- execute isolation ---
if printf '%s' "$execute_block" | grep -E '^[[:space:]]*secrets:' >/dev/null; then
  echo "execute job must not declare job-level secrets:" >&2
  exit 1
fi
for forbidden in \
  'secrets.CALLBACK_SECRET' \
  'secrets.BACKEND_URL' \
  'secrets.HIDDEN_TESTS_TOKEN' \
  'secrets.WORKSPACE_READ_TOKEN' \
  'HIDDEN_INSTALLATION_TOKEN' \
  'secrets.EVALUATOR_APP_PRIVATE_KEY' \
  'vars.EVALUATOR_APP_CLIENT_ID' \
  'create-github-app-token'
do
  if printf '%s' "$execute_block" | grep -F "$forbidden" >/dev/null; then
    echo "$forbidden must not appear in execute job" >&2
    exit 1
  fi
done

if ! grep -F 'assert_execute_env.sh' "$WF" >/dev/null; then
  echo "execute must run assert_execute_env.sh after decrypt" >&2
  exit 1
fi

# --- submit isolation ---
if printf '%s' "$submit_block" | grep -F 'participantRepo' >/dev/null; then
  echo "submit must not reference participantRepo / checkout work" >&2
  exit 1
fi
if ! printf '%s' "$submit_block" | grep -F 'CALLBACK_SECRET' >/dev/null; then
  echo "submit must use CALLBACK_SECRET" >&2
  exit 1
fi
for forbidden in \
  HIDDEN_INSTALLATION_TOKEN \
  'secrets.EVALUATOR_APP_PRIVATE_KEY' \
  'vars.EVALUATOR_APP_CLIENT_ID' \
  create-github-app-token \
  'secrets.PREPARE_WRAP_SECRET' \
  'secrets.WORKSPACE_READ_TOKEN' \
  'secrets.HIDDEN_TESTS_TOKEN'
do
  if printf '%s' "$submit_block" | grep -F "$forbidden" >/dev/null; then
    echo "$forbidden must not appear in submit job" >&2
    exit 1
  fi
done
if ! grep -F 'assert_submit_env.sh' "$WF" >/dev/null; then
  echo "submit must run assert_submit_env.sh" >&2
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
