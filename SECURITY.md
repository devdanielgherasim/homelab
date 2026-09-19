# Security Policy

This repository is public. It documents and automates a home Kubernetes lab.
It is not a production service and holds no customer data — but real
infrastructure (a homelab reachable over Tailscale) is described here, so
security issues are taken seriously.

## Reporting a vulnerability or leaked secret

Do not open a public GitHub issue for:

- a credential, token, or key you found committed in this repository
- a vulnerability in the automation that could expose the homelab's
  management plane

Instead, email **<contact@danielgherasim.com>** with details. You'll get an
acknowledgment and a fix or rotation timeline.

## If a real secret is ever committed to this repository

Deleting a secret in a later commit does **not** remove it from Git
history. The response order is:

1. **Treat the secret as compromised immediately** — assume it has been
   scraped, regardless of how quickly it's removed.
2. **Rotate or revoke it at the source** (GitHub token, Tailscale key,
   Proxmox API token, SSH key, age key, etc.) before doing anything else in
   Git.
3. **Clean Git history** where practical (e.g. `git filter-repo`) — after
   rotation, not instead of it. History rewriting on a public repo requires
   a force-push and is disruptive; only do it when the exposure is
   significant enough to justify it, and force-push is never automatic —
   see `AGENTS.md`'s destructive-action policy.
4. **Document the incident** in `docs/security/public-repository.md`
   (what leaked, when, remediation) **without reproducing the secret
   itself**.

## Scope of this policy

Full threat model, secret-handling strategy, and self-hosted-runner trust
boundary: see [`docs/security/public-repository.md`](docs/security/public-repository.md)
and [`docs/security/self-hosted-runners.md`](docs/security/self-hosted-runners.md).
