#!/usr/bin/env bash
# Integrity guard: verify the participant did not modify any protected file (tests/config/spec).
# Emits protectedFilesIntact=true|false. A mismatch => the backend scores the submission 0.
#
# Usage: verify_integrity.sh <manifest.json> <participant_work_dir>
set -euo pipefail

MANIFEST="$1"
WORK="$2"

intact=true
reason=""

# Every protected file must exist AND hash-match the manifest.
while IFS=$'\t' read -r path expected; do
  actual="$(shasum -a 256 "$WORK/$path" 2>/dev/null | cut -d' ' -f1 || true)"
  if [[ -z "$actual" ]]; then
    intact=false
    reason="missing:$path"
    break
  fi
  if [[ "$actual" != "$expected" ]]; then
    intact=false
    reason="modified:$path"
    break
  fi
done < <(jq -r '.protectedFiles | to_entries[] | [.key, .value] | @tsv' "$MANIFEST")

jq -n --argjson intact "$intact" --arg reason "$reason" \
  '{protectedFilesIntact: $intact, reason: $reason}'
