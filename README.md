# prompt-arena/evaluator (TRUSTED, founder-write-only)

🔴 **This repo is the authoritative scorer (ADR 0001 + ADR 0002).** It runs evaluation for every
submission in isolated GitHub Actions jobs, emits component signals, and POSTs an **HMAC-signed**
callback. Public for free CI minutes; **branch-protect so only the founder can change it**.

## Trust stages (prepare → execute → submit)

| Job | May have | Must not |
|---|---|---|
| **prepare** | Short-lived **GitHub App installation tokens** (minted in-job), `PREPARE_WRAP_SECRET` | Run participant code; long-lived PATs |
| **execute** | Prepared blob; wrap secret **only** on the decrypt step | Job-level secrets; App key; installation tokens; `CALLBACK_SECRET`; shared cache |
| **submit** | `CALLBACK_SECRET`, `BACKEND_URL` + `components.json` | App credentials; install tokens; wrap secret; download participant/hidden code |

Hidden tests transit between prepare and execute only inside an **AES-encrypted** artifact (`PREPARE_WRAP_SECRET`),
because this repo is public and cleartext Actions artifacts are downloadable. Trusted scripts always come from
the evaluator checkout — never from the artifact.

## GitHub App authentication (required)

`prepare` mints **short-lived installation tokens** via SHA-pinned `actions/create-github-app-token`:

1. Token scoped to `promptarena-workspaces/<workspace-repo>` → private workspace checkout (`persist-credentials: false`).
2. Token scoped to `prompt-arena/hidden-<slug>` → hidden-tests clone (env `HIDDEN_INSTALLATION_TOKEN` on the prepare step only).

Use a **dedicated evaluator GitHub App** with least privilege:

- **Contents: Read**
- **Metadata: Read**
- **No Administration**
- Installed on `promptarena-workspaces` (all or selected workspace repos) and on `prompt-arena` (selected `hidden-*` repos + this `evaluator` repo is not required for minting)

⛔ Do **not** use long-lived `WORKSPACE_READ_TOKEN` / `HIDDEN_TESTS_TOKEN` PATs.  
⛔ Do **not** put the provisioning App’s **Administration** private key here (blast radius).

## Required Actions configuration

| Name | Type | Jobs | Purpose |
|---|---|---|---|
| `EVALUATOR_APP_CLIENT_ID` | **Variable** | prepare | Dedicated evaluator App Client ID |
| `EVALUATOR_APP_PRIVATE_KEY` | **Secret** | prepare | Dedicated evaluator App private key (PEM) |
| `PREPARE_WRAP_SECRET` | Secret | prepare + execute(decrypt) | Encrypt/decrypt the prepared artifact |
| `CALLBACK_SECRET` | Secret | submit | HMAC key shared with the backend |
| `BACKEND_URL` | Secret | submit | Backend base URL for `POST /api/v1/submissions/{id}/score` |

### Removed (do not set)

| Name | Reason |
|---|---|
| `WORKSPACE_READ_TOKEN` | Replaced by App installation token |
| `HIDDEN_TESTS_TOKEN` | Replaced by App installation token |

## Dispatch inputs (non-secret only)

`submissionId`, `participantRepo` (owner/name under `promptarena-workspaces`), `commitSha`, `challengeSlug`, optional `challengeVersion` (default `1`).

## Local / CI self-tests

```bash
chmod +x .eval/*.sh .eval/selftest/*.sh
.eval/selftest/assert_workflow_isolation.sh
```

`self-test.yml` runs isolation checks on PR/push.

## Registering a challenge

Add `challenges/<slug>/manifest.json` with `challengeId`, `slug`, `hiddenRepo`, and sha256 of every
protected file. Grant the evaluator App **Contents: Read** on that `hidden-*` repo (selected install).
