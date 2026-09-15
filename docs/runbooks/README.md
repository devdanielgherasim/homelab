# Runbooks

Operational procedures for this homelab. Empty until a procedure has
actually been performed and is worth recording — a runbook written before
the operation has ever been run once is a guess, not a runbook.

## Format

Each runbook (`docs/runbooks/<name>.md`) follows the same shape:

1. **Preconditions** — what must be true before starting.
2. **Steps** — the exact procedure.
3. **Verification** — how to confirm it worked.
4. **Rollback** — how to undo it.
5. **Expected downtime** — if any.

Create one with `.claude/skills/write-runbook/SKILL.md`.

## Recovery objective this repository is built around

```
fresh Proxmox installation
        │
        ▼
clone repository
        │
        ▼
provide private runtime configuration/secrets
        │
        ▼
bootstrap
        │
        ▼
recreate infrastructure
        │
        ▼
recreate Kubernetes
        │
        ▼
recreate platform
```

See [`../proxmox/installation.md`](../proxmox/installation.md) for the
first (manual) step and the responsibility model for every step after it.
The full disaster-recovery runbook gets written once this sequence has
actually been executed and verified once — not before.

## Planned runbooks (not yet written)

- Full cluster rebuild from scratch (the sequence above, as an executable procedure)
- etcd snapshot and restore
- Rotating a leaked credential (procedure; see [`../../SECURITY.md`](../../SECURITY.md) for policy)
- Adding a new worker node
- Renewing/rotating the Tailscale auth key
