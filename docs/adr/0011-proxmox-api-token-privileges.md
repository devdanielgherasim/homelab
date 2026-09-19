# 0011. Privilege-separated Proxmox API token with built-in roles

Status: Accepted
Date: 2026-09-19

## Context

OpenTofu needs an identity on Proxmox to clone VMs. Using `root@pam` or a
full administrator would let a leaked token take over the host. Rollout on the
real host showed which permissions a clone actually needs (see
[`../troubleshooting/proxmox-api-token-403-privsep.md`](../troubleshooting/proxmox-api-token-403-privsep.md)).

## Decision

Create a dedicated user `opentofu@pve` and an API token with privilege
separation (`--privsep 1`). Grant three built-in roles to both the user and
the token: `PVEVMAdmin` at `/`, `PVEDatastoreUser` on the one datastore in
use, and `PVESDNUser` on the default SDN zone. The token secret is shown once,
never written to disk or to Git, and supplied to the provider through an
environment variable.

## Alternatives considered

- **`root@pam` token** — unnecessary blast radius.
- **The provider documentation's example role** (about 40 privileges) — the
  documentation itself calls it excessive.
- **A custom role scoped to a resource pool** — the better end state; not done
  yet.

## Consequences

`PVEVMAdmin` granted at `/` applies to every VM on the host, so the token is
narrower than an administrator but broader than least privilege. Follow-up:
replace it with a custom role on a resource pool or `/vms` and verify a clone
still works. The provider also runs with `insecure = true` for Proxmox's
self-signed certificate; pinning the certificate fingerprint or installing a
trusted certificate is part of the same follow-up.
