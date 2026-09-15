# Secret Detection and Prevention

Prevention over cleanup — see
[`public-repository.md`](public-repository.md#incident-procedure-for-a-leaked-secret):
a secret removed in a later commit is still in Git history. This document
covers the tooling; policy is in [`public-repository.md`](public-repository.md)
and [`../../AGENTS.md`](../../AGENTS.md#secrets).

## Two layers, deliberately not redundant

| Layer | Tool | When | Scope |
|---|---|---|---|
| Local | `gitleaks protect --staged` via pre-commit | Before every commit | Staged diff only — fast |
| Local | `.claude/hooks/post-edit.mjs` secret-scan step | After every `Write`/`Edit` | The one file just touched |
| Remote | `gitleaks` (full history, `fetch-depth: 0`) | Every PR/push, weekly cron | Whole repository, catches anything that slipped past local checks or was pushed from elsewhere |

One scanner (`gitleaks`), applied at three points in the workflow, rather
than several overlapping scanners — see the project principle against
redundant tooling.

## Allowlisting

`.gitleaks.toml` allowlists `*.example` files and documentation, since
those intentionally contain placeholder strings like `YOUR_TOKEN_HERE` that
would otherwise false-positive. It does not weaken scanning of real config
files (`*.tfvars`, `*.yaml` outside `*.example`, etc.) — those are excluded
from Git entirely via `.gitignore`, not allowlisted in gitleaks.

## Why third-party Actions are never pinned to a floating ref

Not a theoretical risk: on 2026-03-19 a compromised maintainer credential
was used to force-push credential-stealing malware into 76 of 77
`aquasecurity/trivy-action` tags and all 7 `aquasecurity/setup-trivy` tags
(CVE-2026-33634 / [GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23)).
Any workflow referencing `@master` or an affected tag during the ~12-hour
window had its runner's secrets exfiltrated. This repo's
`security.yml` used `aquasecurity/trivy-action@master` until this was
caught during local tool bootstrap on 2026-09-15 and corrected to the
verified-clean `@v0.35.0`. Full SHA pinning (not just avoiding `@master`)
remains the tracked follow-up — see `validate.yml`'s known-limitation note.

## GitHub-native protections (manual setup, not automatable from here)

Enabling **secret scanning** and **push protection** on the GitHub repo
settings is recommended and complements `gitleaks` (different detection
signatures, and push protection blocks *before* the push completes). This
requires a repository-settings change an agent cannot make — see the
manual-setup list in the bootstrap report.
