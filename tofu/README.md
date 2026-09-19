# tofu/

OpenTofu configuration for Proxmox VM/infrastructure resources — VM
definitions, disks, NICs, cloud-init. See
[`../docs/architecture/infrastructure.md`](../docs/architecture/infrastructure.md)
and [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md)
for the full responsibility model (this directory does **not** own Proxmox
host-level configuration — that's Ansible).

## Layout

```text
tofu/
├── modules/
│   └── proxmox-vm/          # reusable: one VM cloned from the cloud-init template
└── environments/
    └── homelab/              # clones vpn01/cp01/worker01/worker02 — see its own README below
```

## The worker pool

`var.workers` (a map in `terraform.tfvars`, gitignored) is the whole definition of
the workers: one entry per worker, with its VMID and address, and optional
`cores`, `memory` and `disk_size` (defaults: 2 cores, 3584 MB, 64 GB). Adding an
entry adds a worker; removing one removes it. Validation rejects a duplicate VMID
or address, a VMID outside 103-199, and a badly formed address. The VMs are one
`for_each` module call, so nothing else in the code changes.

The `nodes` output lists every VM with its role, VMID and address.
`ansible/inventories/production/tofu_inventory.py` builds the Ansible inventory
from it, and the Ansible roles derive the pool members and the boot order from
that inventory, so a new worker needs no edit in Ansible either. Check the sum of
VM memory against the host's RAM before adding one.

Removing a worker: drain it and delete the node from Kubernetes first, set its
`protection` to false and apply that, then remove the entry. Removal is a
destroy, and follows the destructive-action policy in `AGENTS.md`.

## Prerequisite: the cloud-init template

This directory clones VMs — it doesn't build the base image. Run
`ansible/roles/proxmox_template/` first (via
`ansible/playbooks/proxmox-template.yml`) to create the Ubuntu 24.04
cloud-init template (VMID 9000) these modules clone from.

## Provider

`bpg/proxmox` (not `Telmate/proxmox` — more actively maintained, verified
live 2026-09-15, see `plans/2026-09-15-vm-provisioning.md`). Credentials
via `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN` environment
variables — never in a file in this repo. The token comes from
`ansible/roles/proxmox_bootstrap`'s `api_token` stage.

```bash
export PROXMOX_VE_ENDPOINT="https://<your-proxmox-ip>:8006/"
export PROXMOX_VE_API_TOKEN="opentofu@pve!tofu=<your-token-secret>"
export SSL_CERT_FILE="$HOME/.config/homelab/pve-root-ca.pem"
```

**TLS is verified.** The Proxmox certificate is signed by the cluster's own CA.
Fetch that public certificate once with
`ansible-playbook ... playbooks/proxmox-bootstrap.yml --tags tls_ca`, compare its
fingerprint with the one in the Proxmox UI (Datacenter -> Certificates), and point
`SSL_CERT_FILE` at it (Linux and WSL; Go on Windows uses the system store instead).
`proxmox_insecure` defaults to `false`.

**The token is scoped to a pool.** It can only act on VMs in the `homelab` resource
pool (`var.proxmox_pool`); a new VM must be created with `pool_id` set, which the
module does. See
[ADR-0011](../docs/adr/0011-proxmox-api-token-privileges.md).

**Safety switches in the module.** `protection = true` makes Proxmox itself refuse to
delete a VM or its disks (set it to `false` first when a VM really has to go),
`on_boot` starts the VMs when the host boots, and `reboot_after_update = false` means
an apply never reboots a running node by itself. The boot *order* is not managed
here: changing it needs `Sys.Modify` on `/`, so it is applied by Ansible
(`playbooks/proxmox-vm-startup.yml`) and the module ignores drift on it.

Always read the plan first (`tofu plan`); an in-place update is expected, a
replacement of a VM is not.

## Running from WSL2 against a Windows-mounted repo

If `tofu init` fails with `chmod: operation not permitted` on a file
under `.terraform/` or on `.terraform.lock.hcl`, your WSL2 distro's
`/mnt/*` mount doesn't have the `metadata` option enabled — NTFS mounts
default to faking POSIX permissions without actually supporting `chmod`.
Fix (one-time, requires a WSL restart):

```bash
# in WSL
sudo bash -c 'cat >> /etc/wsl.conf <<EOF

[automount]
options = "metadata"
EOF'
```

Then from PowerShell: `wsl --shutdown`, reopen WSL. A plugin cache
(`TF_PLUGIN_CACHE_DIR` pointed at a native-Linux-filesystem path, e.g.
`~/.cache/tofu-providers`) also avoids re-downloading providers per
module and sidesteps part of this class of issue, but doesn't fully
replace the `metadata` mount fix (the lock file itself still needs to be
written into the project directory on `/mnt/*`).

## Known caveat: disk resize on clone

See [`modules/proxmox-vm/README.md`](modules/proxmox-vm/README.md#known-caveat-disk-resize-on-clone)
— the `bpg/proxmox` provider has open issues around resizing a disk as
part of cloning.

## Rules

- State is never committed — see `.gitignore` and
  [`../docs/security/public-repository.md`](../docs/security/public-repository.md#opentofu-state).
  `.terraform.lock.hcl` **is** committed (OpenTofu's own recommendation —
  pins exact provider versions/hashes); only `.terraform/` (the
  downloaded provider binaries) and `*.tfstate` are ignored.
- Real variable values (`terraform.tfvars`) are never committed; only
  `terraform.tfvars.example` with placeholder values is.
- `tofu apply` / `tofu destroy` are never run by an agent or a hook without
  explicit human approval — see
  [`../AGENTS.md`](../AGENTS.md#destructive-action-policy). Neither has
  been run against the real host as of this writing — `init`/`validate`/
  `fmt` only.
- `tofu fmt -check -recursive && tofu validate` must pass before commit —
  enforced in CI (`.github/workflows/validate.yml`), and both currently
  pass (verified live in WSL2).

## Status

`proxmox-vm` module + `homelab` environment: **deployed and verified**.
`tofu apply` run against `pve01` on 2026-09-16 — all 4 VMs created and
confirmed reachable (ping, SSH, `cloud-init status`). Required a custom
Proxmox RBAC fix beyond `PVEVMAdmin` alone — see
`ansible/roles/proxmox_bootstrap/tasks/api_token.yml` and
`plans/2026-09-15-vm-provisioning.md`. See [`../STATUS.md`](../STATUS.md)
for full per-VM state.
