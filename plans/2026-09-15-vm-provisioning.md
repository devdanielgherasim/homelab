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
- [x] User ran the Ansible template role, then `tofu init`/`plan`/`apply`
      against the real host (2026-09-16) — `Apply complete! Resources: 4
      added, 0 changed, 0 destroyed.` All 4 VMs verified: ping + SSH +
      `cloud-init status` = `done` on `vpn01`/`cp01`/`worker01`/`worker02`.

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

## Real-host rollout (2026-09-16) — three RBAC gaps found via actual 403s, fixed one at a time

`tofu apply` failed three separate times against the real host, each with
a different `403 Permission check failed`, each root-caused via live
verification (not guessed) and fixed in `ansible/roles/proxmox_bootstrap/tasks/api_token.yml`:

1. **`VM.Clone` on `/vms/9000`** — the `api_token` stage's original ACL
   grant (`pveum acl modify / --users ... --roles PVEVMAdmin`) only
   granted the role to the **user**. The token was created with
   `--privsep 1`, which makes its effective permissions the
   *intersection* of the user's ACLs and the token's own ACLs — with no
   ACL on the token principal (`opentofu@pve!tofu`) itself, that
   intersection was empty. Fixed: grant the same role to the token too
   (`pveum acl modify / -token 'user!token' -role ...`).
2. **`Datastore.AllocateSpace` on `/storage/local-lvm`** — `PVEVMAdmin`
   does not include this privilege; it's a separate Proxmox permission
   namespace, confirmed against a matching Proxmox forum thread about
   disk resizing. Fixed: additionally granted `PVEDatastoreUser` on
   `/storage/<datastore_id>`, to both user and token.
3. **`SDN.Use` on `/sdn/zones/localnetwork/vmbr0`** — Proxmox VE 9
   introduced SDN-layer permission checks even for the default Linux
   bridge (`vmbr0` lives in the built-in `localnetwork` zone). Neither of
   the above roles covers it. Fixed: additionally granted `PVESDNUser` on
   `/sdn/zones/<zone>`, to both user and token — `PVESDNUser` confirmed as
   the correct built-in role via live search, not invented.

Deliberately did NOT grant the "kitchen sink" custom role from the
`bpg/proxmox` provider's own example docs (~40 privileges, explicitly
labeled "most likely too excessive for most use cases" in that doc) —
kept to the three narrowly-scoped built-in roles actually exercised by
this workflow, consistent with the project's least-privilege stance.

Also found: `vpn01` (1GB RAM) showed high memory usage during first boot
— cloud-init's first-run work (user/network setup, package operations)
is genuinely heavy relative to 1GB. Resolved on its own (cloud-init
`status: done`, SSH confirmed) — the Proxmox UI's memory percentage
likely counted reclaimable page cache, not real pressure. Not resized;
flagged here in case it recurs on a future rebuild.

Also found: a `for ip in ...; do ... $ip ...; done` shell loop run
through `wsl.exe -d Ubuntu-24.04 -- bash -c '...'` from this session
silently emptied `$ip` on every iteration (loop count was right, variable
value wasn't) — root-caused by testing a minimal reproduction
(`echo "ip is [$ip]"`) before assuming the fix. Worked around by using
one explicit non-looped SSH command per host instead of chasing the
interpolation bug further; each of the 4 VMs was still verified
individually.

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
