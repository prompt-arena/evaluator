#!/usr/bin/env bash
# Build the canonical signed payload and POST it to the backend score callback.
# Signs `${timestamp}.${nonce}.${body}` with HMAC-SHA256(CALLBACK_SECRET) so the timestamp+nonce headers are
# cryptographically bound to the body (anti-replay + freshness). Never prints the secret or signature value.
#
# Usage: submit.sh <components.json>
# Requires env: SUBMISSION_ID RUN_ID COMMIT_SHA BACKEND_URL CALLBACK_SECRET
set -uo pipefail

COMPONENTS_FILE="$1"

for v in SUBMISSION_ID RUN_ID COMMIT_SHA BACKEND_URL CALLBACK_SECRET; do
  if [[ -z "${!v:-}" ]]; then echo "submit: $v not set" >&2; exit 1; fi
done

BODY="$(jq -c -n \
  --arg s "$SUBMISSION_ID" \
  --arg r "$RUN_ID" \
  --arg c "$COMMIT_SHA" \
  --slurpfile comp "$COMPONENTS_FILE" \
  '{submissionId:$s, runId:$r, commitSha:$c, components:$comp[0]}')"

TS="$(date +%s)"
NONCE="$(openssl rand -hex 16)"
SIG="$(printf '%s' "${TS}.${NONCE}.${BODY}" | openssl dgst -sha256 -hmac "$CALLBACK_SECRET" | sed 's/^.* //')"

code="$(curl -sS -o /tmp/score_resp.txt -w '%{http_code}' \
  -X POST "${BACKEND_URL%/}/api/v1/submissions/${SUBMISSION_ID}/score" \
  -H 'Content-Type: application/json' \
  -H "X-PA-Signature: sha256=${SIG}" \
  -H "X-PA-Timestamp: ${TS}" \
  -H "X-PA-Nonce: ${NONCE}" \
  --data-binary "${BODY}")"

echo "score callback HTTP ${code}"
[[ "$code" == "200" ]]
