# proxmox-vm

Clones one VM from the Ubuntu 24.04 cloud-init template
(`ansible/roles/proxmox_template/`, VMID 9000 by default) via the
`bpg/proxmox` provider, with static IP/DNS/SSH-key cloud-init
configuration.

## Known caveat: disk resize on clone

The `bpg/proxmox` provider has open, recurring issues around resizing a
disk as part of a clone operation (e.g.
[#781](https://github.com/bpg/terraform-provider-proxmox/issues/781),
[#1747](https://github.com/bpg/terraform-provider-proxmox/issues/1747)) —
the VM and disk can end up correctly sized in Proxmox even when `tofu
apply` reports a resize error. This module includes `disk.size` in the
initial clone for correctness, but **if `tofu apply` fails specifically
on a disk-resize step**:

1. Check the VM in the Proxmox UI/`qm config <vmid>` — it may already be
   the size you asked for despite the reported error.
2. If so, the documented workaround is to drop the `disk` block's `size`
   override on that VM (or add a `lifecycle { ignore_changes = [disk] }`
   in `environments/homelab/main.tf` for that instance) and resize
   separately with `qm resize <vmid> scsi0 <size>` if actually needed.

Not worked around preemptively here because it may not reproduce on the
current provider version (0.113.1) — documented so it's recognizable
instead of alarming if it happens.

## Inputs / outputs

See `variables.tf` / `outputs.tf` — each variable has a description.
Sizing per instance is set in `environments/homelab/main.tf`, matching
`docs/architecture/infrastructure.md`'s table (keep both in sync if
either changes).
