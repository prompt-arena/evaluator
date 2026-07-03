#!/usr/bin/env bash
# Install deps + typecheck the participant workspace. Emits {ok, log tail} JSON.
# Usage: build.sh <participant_work_dir>
set -uo pipefail

WORK="$1"
cd "$WORK"

log="$(npm install --no-audit --no-fund 2>&1 && npx tsc --noEmit 2>&1)"
ok=$?

if [[ $ok -eq 0 ]]; then
  jq -n '{ok: true}'
else
  # Keep only a short tail; never leak full paths/secrets.
  jq -n --arg log "$(printf '%s' "$log" | tail -c 500)" '{ok: false, log: $log}'
fi
