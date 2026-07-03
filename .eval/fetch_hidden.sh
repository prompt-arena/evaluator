#!/usr/bin/env bash
# Clone the PRIVATE hidden-tests repo (read-only token) and stage its tests into the participant workspace.
# 🔴 This is the ONLY script that sees HIDDEN_TESTS_TOKEN. It never runs participant code, and it scrubs the
# cloned repo before returning so nothing but the test files remain. The token is never echoed.
#
# Usage: fetch_hidden.sh <participant_work_dir> <hidden_repo:owner/name>
# Requires env: HIDDEN_TESTS_TOKEN
set -uo pipefail

WORK="$1"
HIDDEN_REPO="$2"
HIDDEN_DIR="$(mktemp -d)"

cleanup() { rm -rf "$HIDDEN_DIR" 2>/dev/null || true; }
trap cleanup EXIT

if [[ -z "${HIDDEN_TESTS_TOKEN:-}" ]]; then
  echo "fetch_hidden: HIDDEN_TESTS_TOKEN not set" >&2
  exit 1
fi

if ! git clone --depth 1 "https://x-access-token:${HIDDEN_TESTS_TOKEN}@github.com/${HIDDEN_REPO}.git" "$HIDDEN_DIR" >/dev/null 2>&1; then
  echo "fetch_hidden: clone failed" >&2
  exit 1
fi

mkdir -p "$WORK/tests/hidden"
cp -R "$HIDDEN_DIR"/tests/hidden/. "$WORK/tests/hidden/"
echo "staged hidden tests"
