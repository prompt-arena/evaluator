#!/usr/bin/env bash
# Clone the PRIVATE hidden-tests repo using a short-lived GitHub App installation token and stage
# its tests into the participant workspace.
# 🔴 This is the ONLY script that sees HIDDEN_INSTALLATION_TOKEN. It never runs participant code, and it
# scrubs the cloned repo before returning so nothing but the test files remain. The token is never echoed.
#
# Usage: fetch_hidden.sh <participant_work_dir> <hidden_repo:owner/name> [defect_config_out]
# Requires env: HIDDEN_INSTALLATION_TOKEN (minted in prepare for prompt-arena/<hidden-*> only)
set -uo pipefail

WORK="$1"
HIDDEN_REPO="$2"
DEFECT_OUT="${3:-}"
HIDDEN_DIR="$(mktemp -d)"

cleanup() { rm -rf "$HIDDEN_DIR" 2>/dev/null || true; }
trap cleanup EXIT

if [[ -z "${HIDDEN_INSTALLATION_TOKEN:-}" ]]; then
  echo "fetch_hidden: HIDDEN_INSTALLATION_TOKEN not set" >&2
  exit 1
fi

# Token is step-scoped; never print it. x-access-token is the GitHub App HTTPS auth form.
if ! git clone --depth 1 "https://x-access-token:${HIDDEN_INSTALLATION_TOKEN}@github.com/${HIDDEN_REPO}.git" "$HIDDEN_DIR" >/dev/null 2>&1; then
  echo "fetch_hidden: clone failed" >&2
  exit 1
fi

mkdir -p "$WORK/tests/hidden"
cp -R "$HIDDEN_DIR"/tests/hidden/. "$WORK/tests/hidden/"

# The defect configuration is answer-key material. It is staged OUTSIDE the work tree so that it is
# not handed to the participant's own test run, and it is optional: a challenge with nothing planted
# simply has no such file in its hidden repository.
if [[ -n "$DEFECT_OUT" ]]; then
  if [[ -f "$HIDDEN_DIR/defects.json" ]]; then
    cp "$HIDDEN_DIR/defects.json" "$DEFECT_OUT"
    echo "staged hidden tests + defect config"
  else
    rm -f "$DEFECT_OUT"
    echo "staged hidden tests (no defect config in hidden repo)"
  fi
else
  echo "staged hidden tests"
fi
