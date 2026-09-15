# 2026-09-15 — VM provisioning (template + OpenTofu)

Goal: provision `vpn01`, `cp01`, `worker01`, `worker02` on `pve01`. Two
prerequisites-then-provisioning pieces, since OpenTofu clones VMs from an
existing template — it doesn't build one from an ISO.

## Tasks

- [x] `ansible/roles/proxmox_template/` — downloads Ubuntu 24.04 cloud
      image (checksum-verified), builds a cloud-init-ready VM template
      (VMID 9000) via `qm`, idempotent
- [x] `docs/architecture/infrastructure.md` — added a disk-size column
- [x] `tofu/modules/proxmox-vm/` — reusable module (provider `bpg/proxmox`)
- [x] `tofu/environments/homelab/` — root config, 4 module instances
- [x] `tofu/environments/homelab/terraform.tfvars.example`
- [x] `.gitignore` checked proactively with `git add -A -n` — clean this
      time; also caught and fixed an unrelated pre-existing bug: this
      repo's `.gitignore` was ignoring `.terraform.lock.hcl`, which
      OpenTofu recommends committing (it pins exact provider
      versions/hashes) — fixed
- [x] `tofu fmt -check`, `tofu validate` — pass for both the module and
      the environment (verified live in WSL2, see environment findings
      below for what it took to get there)
- [x] Docs: `tofu/README.md`, `ansible/README.md`, `STATUS.md` updated
- [ ] User runs the Ansible template role, then `tofu init`/`plan`/`apply`
      against the real host — not done by this session (destructive/real
      infra, needs the user present)

## Environment findings worth keeping

- **A second, different WSL2/`/mnt/*` filesystem limitation**, distinct
  from the `ansible.cfg` "world writable" one found earlier today: `tofu
  init` failed with `chmod: operation not permitted` writing provider
  files and `.terraform.lock.hcl`, because the default `9p`/`drvfs` mount
  for a Windows drive under WSL2 doesn't support real POSIX permissions
  (fakes `rwxrwxrwx` on `ls`, rejects actual `chmod`). Root-caused via
  `mount | grep /mnt/e` before guessing. Fix: add `options = "metadata"`
  under `[automount]` in `/etc/wsl.conf`, then `wsl --shutdown` and
  reopen — applied by the user, verified the mount option afterward
  before retrying. A `TF_PLUGIN_CACHE_DIR` pointed at the native Linux
  filesystem (`~/.cache/tofu-providers`) also helps (shared provider
  cache, faster re-inits) but doesn't fully substitute for the mount fix,
  since the lock file itself must still be written into the
  Windows-mounted project directory.
- Tried to run the `wsl.conf` edit myself via a non-interactive nested
  `wsl.exe -- bash -c 'sudo ...'` call — `sudo` blocked waiting for a
  password with no TTY to prompt on, hung for the full timeout. Stopped
  the task, confirmed the file was untouched, and handed the exact
  commands to the user to run interactively instead. System-level config
  changes requiring a privilege prompt aren't something to script through
  an indirect non-interactive shell.
- Confirmed live (not assumed): `bpg/proxmox` provider over `Telmate/proxmox`;
  exact `qm`/cloud-image commands for template creation; the
  `--scsi0 <storage>:0,import-from=<path>` one-step import (avoids
  guessing the post-`qm importdisk` disk name, which varies by storage
  backend); `bpg/proxmox`'s documented `PROXMOX_VE_ENDPOINT`/
  `PROXMOX_VE_API_TOKEN` env vars; the provider's open disk-resize-on-clone
  issues (documented as a caveat, not silently risked).

## Explicitly NOT done

Neither the Ansible template role nor `tofu apply` has been run against
the real host — both require the user present (real infra changes,
`tofu apply` is explicitly gated by `AGENTS.md`'s destructive-action
policy). `tofu plan` (read-only) is a reasonable next step for the user
to run themselves once `terraform.tfvars` is filled in and the template
exists.

## Design decisions (not ADR-worthy — implementation detail, not a fork with real alternatives)

- Provider: `bpg/proxmox` (v0.113.1) over `Telmate/proxmox` — more
  actively maintained, full OpenTofu compatibility, verified live
  2026-09-15 (not assumed from training data).
- State: local, gitignored (`*.tfstate` already in `.gitignore`). No
  remote backend yet — single operator, zero-cost priority, matches the
  project's own "simplicity first" principle. Revisit only if that stops
  being true.
- Template VMID 9000 — common homelab convention (high ID, clearly not a
  real workload), documented so it doesn't collide with `vpn01`
  (informational, not a real VMID conflict source).
