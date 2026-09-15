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

## GitHub-native protections (manual setup, not automatable from here)

Enabling **secret scanning** and **push protection** on the GitHub repo
settings is recommended and complements `gitleaks` (different detection
signatures, and push protection blocks *before* the push completes). This
requires a repository-settings change an agent cannot make — see the
manual-setup list in the bootstrap report.
