# 0010. Local OpenTofu state for a single operator

Status: Accepted
Date: 2026-09-19

## Context

OpenTofu state for the Proxmox VMs contains VM identifiers, addresses and the
cloud-init configuration. The repository is public, so state must never be
committed. The lab has one operator and a hard zero-recurring-cost
constraint.

## Decision

Use the default local backend. State files are gitignored and stay on the
operator's machine. No remote backend is configured.

## Alternatives considered

- **Remote backend on object storage** (S3-compatible, including a
  self-hosted MinIO) — gives locking and off-machine durability, but adds an
  extra service to run before the platform exists, or a recurring cost.
- **State committed with encryption** — rejected by the public-repository
  policy; see [`../security/public-repository.md`](../security/public-repository.md).

## Consequences

Losing the operator's disk loses the state, and the VMs would have to be
re-imported or recreated. There is no state locking, which is acceptable with
one operator and no CI applying changes. Follow-up: an encrypted copy of the
state outside the repository, and a remote backend once a second operator or
CI-driven applies appear. Revisit at that point.
