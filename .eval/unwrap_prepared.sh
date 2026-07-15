#!/usr/bin/env bash
# execute decrypt step only — unwraps prepare artifact to ./work + ./meta.json
# Requires env: PREPARE_WRAP_SECRET (step-scoped)
set -euo pipefail

ENC="${1:?usage: unwrap_prepared.sh <prepared.tar.gz.enc>}"
if [[ -z "${PREPARE_WRAP_SECRET:-}" ]]; then
  echo "unwrap: PREPARE_WRAP_SECRET not set" >&2
  exit 1
fi

openssl enc -aes-256-cbc -pbkdf2 -d -in "$ENC" -out prepared.tar.gz -pass env:PREPARE_WRAP_SECRET
tar -xzf prepared.tar.gz
rm -f prepared.tar.gz "$ENC"

if [[ ! -d work ]] || [[ ! -f meta.json ]]; then
  echo "unwrap: missing work/ or meta.json" >&2
  exit 1
fi

echo "unwrap: prepared work ready"
