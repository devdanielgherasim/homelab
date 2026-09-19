# 0011. Privilege-separated Proxmox API token, scoped to a pool

Status: Accepted
Date: 2026-09-19 (revised the same day: first written with built-in roles at `/`, then narrowed)

## Context

OpenTofu needs an identity on Proxmox to clone VMs. Using `root@pam` or a
full administrator would let a leaked token take over the host. Rollout on the
real host showed which permissions a clone actually needs (see
[`../troubleshooting/proxmox-api-token-403-privsep.md`](../troubleshooting/proxmox-api-token-403-privsep.md)).

## Decision

Create a dedicated user `opentofu@pve` and an API token with privilege
separation (`--privsep 1`). Grant, to both the user and the token:

- a **custom role `HomelabTofu`** with the 14 privileges a clone-and-configure
  workflow needs (13 for VMs plus `Pool.Audit`, read-only), on the **resource pool `homelab`** (the four lab VMs and the
  template), not on `/`;
- `PVEDatastoreUser` on the one datastore in use and `PVESDNUser` on the default
  SDN zone.

The role leaves out backup, console, migration, snapshots, the guest agent's
file and command privileges, `Pool.Allocate` (changing pool membership) and
`Sys.Modify` (needed to set a VM's boot order, so that setting is applied by
Ansible, not OpenTofu). Nothing is granted on `/`, so the token has no
privileges on the node or on anything outside the pool. The token secret is
shown once, never written to disk or Git, and supplied to the provider through
an environment variable.

The provider verifies TLS: the Proxmox certificate is signed by the cluster's own
CA, which `proxmox_bootstrap --tags tls_ca` copies to the machine running
OpenTofu (`SSL_CERT_FILE`), so `insecure = true` is no longer needed.

## Alternatives considered

- **`root@pam` token** — unnecessary blast radius.
- **The provider documentation's example role** (about 40 privileges) — the
  documentation itself calls it excessive.
- **A custom role scoped to a resource pool** — the better end state; not done
  yet.

## Consequences

Verified on 2026-09-19 with a temporary principal carrying exactly these grants
(and none on `/`), through the real API over verified TLS: a full lifecycle of a
throwaway VM (clone into the pool, configure CPU, memory, cloud-init and
network, grow the disk, power on and off, destroy) succeeded, while running a
command in a VM through the guest agent, reading a file through it, starting a
backup, taking a snapshot and opening a console were all refused with 403.
Outside the pool the token has no privileges.

The pool is now part of the model: a new VM must be created in it (`pool_id`),
or OpenTofu's token cannot manage it. The old broad grant (`PVEVMAdmin` on `/`,
23 privileges including unrestricted command execution in every VM) was removed
after the tests passed; re-adding it is the rollback.

A first `tofu apply` still failed with 403 on `Pool.Allocate`: without
`Pool.Audit` the provider cannot see which pool a VM is in and tries to add every
VM to it. The gap, and why the earlier verification missed it (it only cloned into
the pool, never updated an existing VM's membership), are written up in
[`../troubleshooting/tofu-apply-403-pool-allocate.md`](../troubleshooting/tofu-apply-403-pool-allocate.md).
