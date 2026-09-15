# ansible/

Ansible configuration for everything that isn't Proxmox VM *creation*
(that's `tofu/`) or Kubernetes platform state (that's Argo CD):

- Proxmox host configuration (firewall, users/API tokens, network,
  storage, updates).
- Guest OS configuration (packages, users, SSH hardening, containerd/
  kubeadm prerequisites).
- Kubernetes bootstrap (`kubeadm init`/`join`).

See [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md)
for the full responsibility model and
[`../docs/architecture/infrastructure.md`](../docs/architecture/infrastructure.md)
for sizing/context.

## Layout

```
ansible/
├── ansible.cfg     # roles_path etc. — see "Running from WSL2" below
├── inventories/
│   └── production/
│       ├── hosts.example.yml            # copy to hosts.yml (gitignored), fill in real values
│       └── group_vars/proxmox.yml.example  # copy to proxmox.yml (gitignored)
├── playbooks/
│   ├── proxmox-bootstrap.yml   # implements installation.md steps 1-4 — see its header before running
│   ├── proxmox-template.yml    # builds the cloud-init VM template
│   └── guest-hardening.yml     # SSH hardening + unattended upgrades on the 4 VMs
└── roles/
    ├── proxmox_bootstrap/      # network check, API token, SSH key, firewall — staged, see below
    ├── proxmox_template/       # builds the Ubuntu 24.04 cloud-init VM template tofu/ clones from
    └── guest_hardening/        # SSH defense-in-depth + unattended-upgrades on vpn01/cp01/worker01/worker02
```

## Running from WSL2 against a Windows-mounted repo (`/mnt/e/...`)

Two gotchas specific to this setup, both worth knowing before you're
confused by an error:

1. **`ansible.cfg` gets ignored with a "world writable directory" warning.**
   NTFS mounts under WSL2 (`/mnt/e/...`) report as world-writable to
   Ansible's safety check, so it refuses to auto-load `ansible.cfg` from
   there. Fix: pass it explicitly — `ANSIBLE_CONFIG=./ansible.cfg
   ansible-playbook ...` (from the `ansible/` directory) or
   `ANSIBLE_CONFIG=./ansible/ansible.cfg ansible-lint ansible/` (from the
   repo root).
2. **`ansible-lint` warns about `.yamllint.yaml` being "incompatible."**
   The repo's yamllint config (used for `kubernetes/`, CI, etc.) doesn't
   match ansible-lint's specific opinionated YAML sub-rules
   (`comments-indentation`, `braces.max-spaces-inside`, octal handling).
   This is a known, accepted mismatch — loosening `.yamllint.yaml`
   repo-wide to satisfy ansible-lint's stricter subset would weaken
   linting for every other YAML file in the repo for no real benefit.
   It only disables ansible-lint's `-f` auto-fix mode; it does not affect
   pass/fail.

If mise-managed tools aren't found in a non-interactive shell (`command
not found` despite `make doctor` showing them installed), the shell isn't
sourcing mise's activation — use `~/.local/bin/mise exec -- <command>`
instead of relying on shell rc files.

## The `proxmox_bootstrap` role

Bootstraps a freshly-installed Proxmox host to the point where OpenTofu
can manage it: verifies the management network (read-only), creates a
least-privilege API token for OpenTofu, adds an admin SSH key, and
enables the firewall. **Deliberately staged across 6 tags, run one at a
time with verification between them — read
`playbooks/proxmox-bootstrap.yml`'s header before running anything.** The
two genuinely risky stages (`firewall_enforce`, `ssh_lockdown`) are gated
behind Ansible's `never` tag (require explicit `--tags`) and an
interactive confirmation prompt, and `ssh_lockdown` independently
re-verifies key-based login itself before disabling password auth.

No extra Ansible collections required — deliberately uses
`ansible.builtin.lineinfile` instead of `ansible.posix.authorized_key`,
and the `pveum` CLI on the host instead of `community.general`'s Proxmox
modules (which need `proxmoxer`/`requests` on the controller), to keep
this bootstrap step dependency-free.

## The `proxmox_template` role

Downloads the Ubuntu 24.04 cloud image (checksum-verified against
Canonical's published `SHA256SUMS`) and builds a cloud-init-ready VM
template (VMID 9000 by default) via the `qm` CLI. Idempotent — skips
entirely if the template already exists. Unlike `proxmox_bootstrap`, this
doesn't touch firewall/SSH/existing VMs, so it isn't staged behind
confirmation prompts — run it with `ansible-playbook
playbooks/proxmox-template.yml`.

## The `guest_hardening` role

SSH defense in depth (`PasswordAuthentication no`, `PermitRootLogin no` —
cloud-init never set a password for `ubuntu` in the first place, so this
closes a door that likely doesn't open anyway, unlike `proxmox_bootstrap`'s
`ssh_lockdown` which removed a *working* path) plus unattended security
upgrades with automatic reboot **off** by default
(`guest_hardening_unattended_reboot`, a real toggle if ever wanted).
Deliberately out of scope: guest-level firewall (`ufw`) — the Proxmox
host firewall and, later, Cilium NetworkPolicies are the intended layers,
not a third one; swap-disable (a kubeadm prerequisite, not hardening —
next role); `fail2ban` (no clear benefit on LAN-only, key-only SSH).

## Rules

- Real inventory files, vault passwords, and any host-specific variables
  with real values are never committed — see `.gitignore` and
  [`../docs/security/public-repository.md`](../docs/security/public-repository.md).
- Playbooks that touch the real Proxmox host or a real cluster are never
  run by an agent or a hook without explicit human approval — see
  [`../AGENTS.md`](../AGENTS.md#destructive-action-policy). This session
  wrote `proxmox_bootstrap` but has not run it against real infrastructure.
- `ansible-lint` (profile: production) and `ansible-playbook
  --syntax-check` must pass before commit — enforced in CI, and both
  currently pass for this role.
- `ansible-playbook --check --diff` is the drift-detection mechanism once
  real playbooks exist (see
  [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md#configuration-drift-detection-design)).

## Status

`proxmox_bootstrap` and `proxmox_template`: both deployed and verified
against `pve01`. The `api_token` stage needed a follow-up fix
(3 Proxmox RBAC namespaces, not just `PVEVMAdmin`) found via real
OpenTofu apply 403s — see the header comment in
`roles/proxmox_bootstrap/tasks/api_token.yml`. `guest_hardening`:
generated, statically validated (`ansible-lint` production profile,
`--syntax-check` both pass), **not yet run**. See
[`../STATUS.md`](../STATUS.md).
