#!/usr/bin/env bash
# 🔴 SECURITY REGRESSION TEST — this repository is PUBLIC.
#
# Planted-defect identities and their detection mappings are answer-key material for active
# Challenge versions. Anyone who can read them can pass the Challenge without doing the work, which
# destroys the measurement the platform exists to produce. They belong in the challenge's PRIVATE
# hidden-tests repository and reach the evaluator at runtime through the encrypted prepare artifact.
#
# The checks below are structural rather than a denylist of today's strings, because the failure
# this guards against is someone re-adding the section for the NEXT challenge, whose ids nobody has
# thought to add to a list yet.
#
# Usage: .eval/selftest/assert_no_answer_key.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FAILURES=0
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
ok()   { printf 'ok   %s\n' "$1"; }

# 1. No challenge manifest may carry a defects section. This is the exact regression that put the
#    answer key in a public repo once already.
offenders=""
while IFS= read -r m; do
  if jq -e 'has("defects")' "$m" >/dev/null 2>&1; then
    offenders="$offenders $m"
  fi
done < <(find challenges -name manifest.json -type f 2>/dev/null)

if [[ -n "$offenders" ]]; then
  fail "challenge manifest declares defects (answer key in a public repo):$offenders"
else
  ok "no challenge manifest declares defects"
fi

# 2. No committed file may carry a detection mapping. Catches the section being moved to some other
#    filename in this repo rather than to the private hidden repository.
if hits="$(git ls-files -z \
          | xargs -0 grep -lE '"?(testNames|detectedBy)"?[[:space:]]*:' 2>/dev/null \
          | grep -vE '^\.eval/(detect_defects\.sh|detect_defects\.test\.sh)$' || true)"; [[ -n "$hits" ]]; then
  fail "detection mapping present outside the generic engine: $(echo "$hits" | tr '\n' ' ')"
else
  ok "no detection mapping outside the generic engine"
fi

# 3. The engine and its tests may mention the shape, but only synthetic ids. Any defect id that is
#    not obviously a fixture is treated as production material.
#
#    🔴 The offending value is deliberately NOT printed. This job's logs are public, so echoing the
#    id here would publish the very thing the check exists to keep private; the file name is enough
#    to find it locally.
if hits="$(git ls-files -z \
          | xargs -0 grep -lE '"id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_-]+"' 2>/dev/null \
          | while IFS= read -r f; do
              if grep -hoE '"id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_-]+"' "$f" \
                 | grep -oE '"[A-Za-z0-9_-]+"$' | tr -d '"' \
                 | grep -qvE '^(test_|synthetic_|example_|sample_)'; then printf '%s\n' "$f"; fi
            done || true)"; [[ -n "$hits" ]]; then
  fail "non-synthetic defect id present in: $(echo "$hits" | tr '\n' ' ')(value withheld — logs are public)"
else
  ok "every defect id in this repo is a synthetic fixture"
fi

# 4. The staged config must never be committed here, under any of the names prepare/run use.
if hits="$(git ls-files | grep -E '(^|/)(hidden_defects|defects)\.json$' || true)"; [[ -n "$hits" ]]; then
  fail "defect config committed to the public repo: $(echo "$hits" | tr '\n' ' ')"
else
  ok "no defect config committed to the public repo"
fi

# 5. The config must not be packed into any artifact this repo publishes, and must be scrubbed from
#    the execute runner once detection has read it.
if ! grep -q 'hidden_defects.json' .github/workflows/evaluate.yml; then
  fail "evaluate.yml no longer scrubs the defect config"
elif grep -nE '^\s*(name|path):.*hidden_defects\.json' .github/workflows/evaluate.yml >/dev/null 2>&1; then
  fail "evaluate.yml uploads the defect config as an artifact"
else
  ok "defect config is scrubbed and never uploaded"
fi

if [[ $FAILURES -gt 0 ]]; then
  printf '\nassert_no_answer_key: %d check(s) failed\n' "$FAILURES"
  exit 1
fi

printf '\nassert_no_answer_key: ok\n'
