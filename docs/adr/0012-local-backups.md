# 0012. Backups stay on the Proxmox host, and cover only what has state

Status: Accepted
Date: 2026-09-19

## Context

The lab is a single physical laptop with one disk. It holds no critical data;
its value is the ability to rebuild it. Two kinds of state exist: the desired
state, which is in Git, and the running Kubernetes state, which lives in etcd
on the single control-plane node (`cp01`). The workers and `vpn01` hold no
state: there are no persistent volumes, and they are recreated by OpenTofu and
Ansible.

## Decision

- Back up **etcd** (a verified snapshot plus the cluster PKI, daily, seven
  copies, on `cp01`) and **`cp01` as a whole VM** (Proxmox `vzdump`, daily,
  three copies, in the `local` storage of the Proxmox host).
- Do **not** back up the workers or `vpn01`. Rebuild them from Git.
- Keep every backup on the Proxmox host's own disk. No external disk, NAS or
  cloud copy.

`cp01` gets a VM-level backup as well as the etcd snapshot because the snapshots
live on `cp01`'s own disk: an archive in Proxmox storage is what survives the VM
being destroyed by mistake, without putting an SSH key to Proxmox on the node.

## Alternatives considered

- **`vzdump` of all four VMs** — about 176 GB of provisioned disk to protect
  machines that are disposable by design.
- **Off-host copies (external disk, NAS, encrypted cloud)** — the only
  protection against losing the laptop, but the owner judged the cost not
  worth it for a lab with no critical data.
- **etcd snapshot only** — leaves the snapshots exposed to the same event that
  destroys `cp01`.

## Consequences

If the laptop's disk fails, every backup is lost with it and only Git remains.
That is accepted. Rebuilding then means reinstalling Proxmox and replaying the
automation, which is the recovery objective in
[`../runbooks/README.md`](../runbooks/README.md).

Not covered, and worth knowing: the OpenTofu state file (local, gitignored,
not backed up); the Proxmox host configuration (rebuilt from Ansible); and any
future persistent volume, which will need its own backup. The scope must be
reviewed as soon as a workload with persistent data is added, because the
"workers are disposable" premise ends there.
