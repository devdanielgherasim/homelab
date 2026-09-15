---
name: security-review
description: >
  Check a diff, PR, or set of files against this repository's public-repo
  and infrastructure security policy — secret exposure, real-topology
  leaks, GitHub Actions trust-boundary violations, .gitignore coverage.
  Use before a commit/PR involving CI workflows, docs with network/infra
  detail, or anything touching secrets, and whenever explicitly asked for
  a security review.
---

# security-review

## Input

A diff, PR number/branch, or explicit file list.

## Checklist

Full policy lives in `docs/security/public-repository.md` and
`docs/security/self-hosted-runners.md` — this is the checklist form of it:

1. **Secrets** — any password, token, private key, kubeconfig with
   credentials, vault password, or `.env` real value? Run/consider
   `gitleaks detect` on the diff. Check `.gitignore` actually covers the
   file pattern involved, not just that this one file looks clean.
2. **Real network/hardware identity** — real LAN CIDR, public IP, DDNS
   hostname, ISP name, router make/model, MAC address, hardware serial,
   Tailscale device identity? These aren't caught by a secret scanner —
   read for them explicitly.
3. **GitHub Actions trust boundary** (only if `.github/workflows/**`
   changed) — does any trigger (`pull_request_target`, `workflow_run`)
   expose secrets or a self-hosted/privileged runner to untrusted input?
   Is `permissions:` scoped per-job rather than broad at workflow level?
   Are third-party actions pinned to a commit SHA?
4. **State/plan files** — any `*.tfstate`, `*.tfplan`, or similar meant to
   never be committed?
5. **CI log exposure** — any new step that could print an environment
   dump, kubeconfig, token, or verbose Ansible output with secret vars?

## Output

Findings by severity (block-worthy vs. advisory), each with the specific
file/line and fix. If clean, say so in one line — don't pad. This is the
same checklist `.claude/agents/reviewer.md` applies as its #1 priority;
either can be used depending on whether a full adversarial review or just
this focused pass is needed.
