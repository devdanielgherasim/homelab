# tofu/

OpenTofu configuration for Proxmox VM/infrastructure resources — VM
definitions, disks, NICs, cloud-init. See
[`../docs/architecture/infrastructure.md`](../docs/architecture/infrastructure.md)
and [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md)
for the full responsibility model (this directory does **not** own Proxmox
host-level configuration — that's Ansible).

## Layout

```
tofu/
├── modules/
│   └── proxmox-vm/          # reusable: one VM cloned from the cloud-init template
└── environments/
    └── homelab/              # clones vpn01/cp01/worker01/worker02 — see its own README below
```

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
```

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
