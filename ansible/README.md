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

```text
ansible/
├── ansible.cfg     # roles_path etc. — see "Running from WSL2" below
├── inventories/
│   └── production/
│       ├── hosts.example.yml            # copy to hosts.yml (gitignored), fill in real values
│       └── group_vars/*.yml.example        # copy to *.yml (gitignored): proxmox, vpn_gateway
├── playbooks/
│   ├── proxmox-bootstrap.yml   # implements installation.md steps 1-4 — see its header before running
│   ├── proxmox-template.yml    # builds the cloud-init VM template
│   ├── guest-hardening.yml     # SSH hardening + unattended upgrades on the 4 VMs
│   ├── tailscale.yml           # vpn01 as a Tailscale subnet router
│   ├── guest-agent.yml         # qemu-guest-agent in the 4 VMs
│   ├── etcd-backup.yml         # daily verified etcd snapshot on cp01
│   ├── proxmox-backup.yml      # scheduled vzdump of cp01 on the Proxmox host
│   └── k8s-bootstrap.yml       # containerd + kubeadm init/join on cp01/worker01/worker02
└── roles/
    ├── proxmox_bootstrap/      # network check, API token, SSH key, firewall — staged, see below
    ├── proxmox_template/       # builds the Ubuntu 24.04 cloud-init VM template tofu/ clones from
    ├── guest_hardening/        # SSH defense-in-depth + unattended-upgrades on vpn01/cp01/worker01/worker02
    ├── qemu_guest_agent/       # guest side of the Proxmox agent channel — the 4 VMs
    ├── etcd_backup/            # etcdctl/etcdutl at the running version, snapshot script + systemd timer — cp01
    ├── proxmox_backup/         # cluster-level vzdump job via pvesh — Proxmox host
    ├── tailscale/              # Tailscale client from the signed apt repo, IP forwarding, tailnet join — vpn01 only
    ├── kubeadm_prereqs/        # containerd, kubeadm/kubelet/kubectl, swap/kernel/sysctl — all k8s nodes
    ├── kubeadm_init/           # `kubeadm init` — cp01 only
    └── kubeadm_join/           # `kubeadm join` — worker01/worker02 only
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
2. **Both linters share one YAML config.** `.yamllint.yaml` is kept
   compatible with ansible-lint's own YAML rules, so `yamllint` and
   `ansible-lint` agree and no "incompatible configuration" warning
   appears. Run `ANSIBLE_CONFIG=./ansible/ansible.cfg ansible-lint` from
   the repo root.

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

## The `kubeadm_prereqs` / `kubeadm_init` / `kubeadm_join` roles

Bootstraps a real Kubernetes cluster via `playbooks/k8s-bootstrap.yml`,
targeting `cp01`/`worker01`/`worker02` (`vpn01` is never a cluster
member). Three separate roles, not one, because they have different
idempotency shapes and target different hosts:

- **`kubeadm_prereqs`** (all 3 nodes): swap off, `overlay`/`br_netfilter`
  kernel modules, sysctl, containerd (Docker's apt repo,
  `SystemdCgroup = true`), and `kubeadm`/`kubelet`/`kubectl` from
  `pkgs.k8s.io` (the current repo — the old `apt.kubernetes.io` is dead),
  held at their installed version via `dpkg_selections` so a stray `apt
  upgrade` can't silently jump the cluster to a new minor version. Uses
  `ansible.builtin.deb822_repository`, not the deprecated
  `apt_repository` (removed in ansible-core 2.25) — it downloads and
  manages the signing key itself, no manual `gpg --dearmor` step needed.
- **`kubeadm_init`** (`cp01` only): idempotency here is load-bearing, not
  optional — `kubeadm init` isn't safely re-runnable, and `kubeadm reset`
  is explicitly in `AGENTS.md`'s destructive-action policy and is never
  run by this role. Guarded by checking `/etc/kubernetes/admin.conf`.
  Always (re)creates a join token afterward regardless (safe/idempotent),
  exposed to other hosts via `hostvars` for `kubeadm_join`.
- **`kubeadm_join`** (`worker01`/`worker02`): guarded by checking
  `/etc/kubernetes/kubelet.conf`; reads the join command from
  `hostvars['cp01']` — requires `k8s-bootstrap.yml`'s play order
  (control plane before workers) within the same run.

Pod network CIDR (`10.244.0.0/16`) matches
[`../docs/architecture/networking.md`](../docs/architecture/networking.md)'s
documented Cilium pod CIDR. **Nodes will show `NotReady` in `kubectl get
nodes` until Cilium is installed — expected, not a failure of this role.**

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

All five roles (`proxmox_bootstrap`, `proxmox_template`, `guest_hardening`,
`kubeadm_prereqs`/`kubeadm_init`/`kubeadm_join`) are deployed and verified
against the real hosts. Two real bugs found and fixed via actual rollout
failures, not caught by static validation alone: `api_token` needed 3
Proxmox RBAC namespaces, not just `PVEVMAdmin` (real `tofu apply` 403s —
see `roles/proxmox_bootstrap/tasks/api_token.yml`); `kubeadm_init` failed
on a default-disabled containerd CRI plugin shipped by the `containerd.io`
apt package (see `roles/kubeadm_prereqs/tasks/containerd.yml`). See
[`../STATUS.md`](../STATUS.md).

## Tailscale gateway (`vpn01`)

`playbooks/tailscale.yml` turns `vpn01` into a Tailscale subnet router. The
tailnet side is configured once in the Tailscale admin console (identity
provider with MFA, `tag:vpn` in `tagOwners`, `autoApprovers` for the routes, a
policy that limits access to management ports). That policy names real
addresses and is not kept in this repository.

1. Put the routes to advertise in the gitignored
   `inventories/production/group_vars/vpn_gateway.yml` (copy the `.example`).
   Prefer `/32` routes for the hosts you administer over a whole LAN.
2. Generate a single-use, tagged, short-lived auth key in the console and put
   it in a root-only file on the machine running Ansible, never on a command
   line: `read -rs k; umask 077; printf '%s' "$k" > ~/.ts-authkey; unset k`.
3. Dry run, then apply (the key file is only read while the host is not yet
   in the tailnet):

   ```bash
   ansible-playbook -i inventories/production/hosts.yml playbooks/tailscale.yml \
     --private-key ~/.ssh/homelab_admin_ed25519 --check --diff
   TS_AUTHKEY_FILE=~/.ts-authkey ansible-playbook -i inventories/production/hosts.yml \
     playbooks/tailscale.yml --private-key ~/.ssh/homelab_admin_ed25519
   ```

4. Delete the key file. Re-running the playbook later keeps the advertised
   routes in sync without needing a key.

`-e tailscale_join=false` installs and configures without joining a tailnet.
The role is covered by `scripts/test-roles.sh`, which never joins.
