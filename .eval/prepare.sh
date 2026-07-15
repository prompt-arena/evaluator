#!/usr/bin/env bash
# prepare job only: stage workspace + (if intact) hidden tests; encrypt for artifact transit.
# 🔴 Never executes participant code. Never echoes tokens/secrets.
#
# Requires env: HIDDEN_TESTS_TOKEN PREPARE_WRAP_SECRET SUBMISSION_ID COMMIT_SHA
#               CHALLENGE_SLUG CHALLENGE_VERSION WORKSPACE_REPO
# Expects: ./work (checked out), ./challenges, ./.eval
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
cd "$ROOT"

for v in PREPARE_WRAP_SECRET SUBMISSION_ID COMMIT_SHA CHALLENGE_SLUG WORKSPACE_REPO; do
  if [[ -z "${!v:-}" ]]; then echo "prepare: $v not set" >&2; exit 1; fi
done

CHALLENGE_VERSION="${CHALLENGE_VERSION:-1}"
if ! [[ "$CHALLENGE_VERSION" =~ ^[0-9]+$ ]]; then
  echo "prepare: challengeVersion must be a non-negative integer" >&2
  exit 1
fi
MANIFEST="challenges/${CHALLENGE_SLUG}/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "prepare: unknown challenge manifest: $MANIFEST" >&2
  exit 1
fi

# Drop VCS metadata so the artifact cannot carry checkout credentials.
rm -rf work/.git

INTEG="$("$DIR/verify_integrity.sh" "$MANIFEST" work)"
intact="$(printf '%s' "$INTEG" | jq -r '.protectedFilesIntact')"
echo "protectedFilesIntact=$intact"

if [[ "$intact" == "true" ]]; then
  if [[ -z "${HIDDEN_TESTS_TOKEN:-}" ]]; then
    echo "prepare: HIDDEN_TESTS_TOKEN not set" >&2
    exit 1
  fi
  "$DIR/fetch_hidden.sh" work "$(jq -r '.hiddenRepo' "$MANIFEST")"
else
  echo "prepare: skipping hidden fetch (integrity failed)"
fi

jq -n \
  --arg submissionId "$SUBMISSION_ID" \
  --arg commitSha "$COMMIT_SHA" \
  --arg challengeSlug "$CHALLENGE_SLUG" \
  --argjson challengeVersion "$CHALLENGE_VERSION" \
  --arg workspaceRepo "$WORKSPACE_REPO" \
  --argjson intact "$intact" \
  --argjson integrity "$INTEG" \
  '{
    submissionId: $submissionId,
    commitSha: $commitSha,
    challengeSlug: $challengeSlug,
    challengeVersion: $challengeVersion,
    workspaceRepo: $workspaceRepo,
    protectedFilesIntact: $intact,
    integrity: $integrity
  }' > meta.json

# Pack only work/ + meta.json — trusted scripts come from the evaluator checkout in later jobs.
tar -czf prepared.tar.gz work meta.json

# Encrypt so public-repo artifact downloads cannot read hidden tests in cleartext.
# Key is Actions secret PREPARE_WRAP_SECRET (prepare encrypt + execute decrypt step only).
openssl enc -aes-256-cbc -pbkdf2 -salt \
  -in prepared.tar.gz \
  -out prepared.tar.gz.enc \
  -pass env:PREPARE_WRAP_SECRET

rm -f prepared.tar.gz
# Scrub cleartext work from the prepare runner before job end.
rm -rf work
echo "prepare: encrypted artifact ready"
