# prompt-arena/evaluator (TRUSTED, founder-write-only)

🔴 **This repo is the authoritative scorer (ADR-0001).** It runs the evaluation for every submission in an
isolated GitHub Actions run, computes component scores, enforces protected-file integrity, and POSTs an
**HMAC-signed** result to the backend. It is public (for free CI minutes) but **must be branch-protected so
only the founder can change it** — participants must never be able to modify the workflow/scripts or read
its secrets.

## Trust boundary rules
- The authoritative `evaluate.yml` + `.eval/*` and ALL secrets live here — never in the public challenge
  repo (which may only carry an untrusted, secretless `practice.yml`) and never in the backend monorepo.
- The runner is **not** authoritative for the final score: it emits `components` + a signed payload; the
  **backend recomputes and decides** the final score.
- Secrets come from this repo's **Actions secrets**, never from `workflow_dispatch` inputs (inputs leak in
  public logs).

## Required Actions secrets
| Secret | Purpose |
|---|---|
| `HIDDEN_TESTS_TOKEN` | Fine-grained, **read-only** token for the private `hidden-<slug>` repo. Only `fetch_hidden.sh` sees it. |
| `CALLBACK_SECRET` | HMAC key shared with the backend to sign the score payload. |
| `BACKEND_URL` | Base URL the backend exposes (`https://…`) for the score callback. |

## Flow (`.eval/`)
1. `verify_integrity.sh` — hash protected files vs `challenges/<slug>/manifest.json`; tamper ⇒ score 0.
2. `fetch_hidden.sh` — clone the private hidden tests (token) and stage them; **only** step with the token.
3. `run.sh` — integrity + `build.sh` + `run_public_tests.sh` + `run_hidden_tests.sh` + `quality.sh` →
   canonical `components` JSON. Runs participant code **with no secrets in scope**.
4. `submit.sh` — build `{submissionId, runId, commitSha, components}`, sign `${ts}.${nonce}.${body}` with
   `CALLBACK_SECRET`, POST to `BACKEND_URL/api/v1/submissions/{id}/score` with `X-PA-Signature/Timestamp/Nonce`.

## Registering a challenge
Add `challenges/<slug>/manifest.json` with `challengeId`, `slug`, `hiddenRepo`, and the sha256 of every
protected file. The backend dispatches with inputs: `submissionId`, `participantRepo`, `commitSha`,
`challengeSlug`.

> **Hardening TODO before beta:** pin `actions/*` to commit SHAs; add branch protection (founder-only).
