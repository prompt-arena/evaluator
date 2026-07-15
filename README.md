# prompt-arena/evaluator (TRUSTED, founder-write-only)

🔴 **This repo is the authoritative scorer (ADR 0001 + ADR 0002).** It runs evaluation for every
submission in isolated GitHub Actions jobs, emits component signals, and POSTs an **HMAC-signed**
callback. Public for free CI minutes; **branch-protect so only the founder can change it**.

## Trust stages (prepare → execute → submit)

| Job | May have | Must not |
|---|---|---|
| **prepare** | `WORKSPACE_READ_TOKEN`, `HIDDEN_TESTS_TOKEN`, `PREPARE_WRAP_SECRET` | Run participant code |
| **execute** | Prepared blob; wrap secret **only** on the decrypt step | Job-level secrets; `CALLBACK_SECRET`; shared cache |
| **submit** | `CALLBACK_SECRET`, `BACKEND_URL` + `components.json` | Download participant code or hidden tests |

Hidden tests transit between prepare and execute only inside an **AES-encrypted** artifact (`PREPARE_WRAP_SECRET`),
because this repo is public and cleartext Actions artifacts are downloadable. Trusted scripts always come from
the evaluator checkout — never from the artifact.

## Required Actions secrets

| Secret | Jobs | Purpose |
|---|---|---|
| `WORKSPACE_READ_TOKEN` | prepare | Read private `promptarena-workspaces/*` (or public participant repo) at commit |
| `HIDDEN_TESTS_TOKEN` | prepare | Read-only clone of `prompt-arena/hidden-<slug>` |
| `PREPARE_WRAP_SECRET` | prepare + execute(decrypt) | Encrypt/decrypt the prepared artifact |
| `CALLBACK_SECRET` | submit | HMAC key shared with the backend |
| `BACKEND_URL` | submit | Backend base URL for `POST /api/v1/submissions/{id}/score` |

## Dispatch inputs (non-secret only)

`submissionId`, `participantRepo` (owner/name), `commitSha`, `challengeSlug`, optional `challengeVersion` (default `1`).

Backend today sends the first four (compatible). Signed callback body also includes `workspaceRepo` +
`challengeVersion` (extra fields; backend HMAC verifies raw body and ignores unknown JSON properties until
binding is enforced server-side).

## Local / CI self-tests

```bash
chmod +x .eval/*.sh .eval/selftest/*.sh
.eval/selftest/assert_workflow_isolation.sh
```

`self-test.yml` runs isolation checks on PR/push.

## Registering a challenge

Add `challenges/<slug>/manifest.json` with `challengeId`, `slug`, `hiddenRepo`, and sha256 of every
protected file.
