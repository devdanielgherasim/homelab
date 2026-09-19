# 2026-09-16 — containerd + kubeadm bootstrap

Goal: bootstrap a real (CNI-less, expected `NotReady` until Cilium)
Kubernetes cluster on `cp01`/`worker01`/`worker02`. `vpn01` is not a
cluster member — excluded from all k8s_* groups.

## Verified live before writing anything (not assumed)

- `pkgs.k8s.io` is the current repo (the old `apt.kubernetes.io` is dead);
  `core:/stable:/v1.37/deb/` exists and is current stable as of
  2026-09-16 (matches `kubectl` already pinned in `mise.toml`, avoiding
  version skew — kubectl should stay within 1 minor of the cluster).
- containerd from Docker's apt repo + `SystemdCgroup = true` is the
  current documented best practice for kubeadm on Ubuntu 24.04.
- Standard prerequisites (swap off, `overlay`/`br_netfilter` modules,
  the three sysctl keys) are unchanged and current.

## Design

Three roles, not one — different idempotency shapes and different hosts:

- `kubeadm_prereqs` — swap off, kernel modules, sysctl, containerd,
  kubeadm/kubelet/kubectl packages (held at the installed version via
  `dpkg_selections`, not auto-upgraded by a stray `apt upgrade`). Runs on
  all 3 k8s nodes (`k8s_nodes` group = `k8s_control_plane` + `k8s_workers`).
- `kubeadm_init` — runs only on `cp01`. **Idempotency is load-bearing
  here, not optional**: `kubeadm init` is not safely re-runnable, and
  `kubeadm reset` is explicitly in `AGENTS.md`'s destructive-action
  policy (never run by this role, ever). Guarded by checking whether
  `/etc/kubernetes/admin.conf` already exists. Always (re)creates a join
  token afterward regardless of whether init just ran — token creation
  is safe/idempotent, and later re-runs of `kubeadm_join` need a fresh
  one available via `hostvars['cp01']`.
- `kubeadm_join` — runs on `worker01`/`worker02`. Guarded by checking
  `/etc/kubernetes/kubelet.conf`; uses the join command computed by
  `kubeadm_init` on `cp01` via `hostvars`, in one playbook run where
  `k8s-bootstrap.yml`'s play order puts the control plane first.

Pod network CIDR: `10.244.0.0/16`, matching
`docs/architecture/networking.md`'s documented Cilium pod CIDR — not
invented here, kept in sync (duplicated with a comment, not a fragile
cross-role default dependency) between `kubeadm_prereqs` and
`kubeadm_init` defaults.

## Tasks

- [x] Inventory: `k8s_control_plane`, `k8s_workers`, `k8s_nodes` groups
      (both `hosts.example.yml` and the real, gitignored `hosts.yml`)
- [x] `ansible/roles/kubeadm_prereqs/`
- [x] `ansible/roles/kubeadm_init/`
- [x] `ansible/roles/kubeadm_join/`
- [x] `ansible/playbooks/k8s-bootstrap.yml`
- [x] `ansible-lint` (production profile) — pass; caught a real,
      non-cosmetic finding: `ansible.builtin.apt_repository` (used for
      both the Docker and Kubernetes apt repos) is deprecated and slated
      for removal in ansible-core 2.25. Switched both to
      `ansible.builtin.deb822_repository`, which also let the manual
      `gpg --dearmor` key-handling steps be dropped entirely (the module
      downloads and manages the signing key itself). 4 other minor
      findings (handler naming, a `no-handler` debug task, Jinja
      spacing) also fixed.
- [x] `--syntax-check` — pass
- [x] `gitleaks` — clean
- [x] Docs: `ansible/README.md`, `STATUS.md` updated
- [x] User ran it against the real hosts (2026-09-16). `kubeadm_prereqs`
      succeeded cleanly on all 3 nodes. `kubeadm_init` failed on `cp01`:
      `[ERROR CRI]: ... unknown service runtime.v1.RuntimeService`.
      Root-caused via direct SSH, not guessed: the `containerd.io` apt
      package ships a default `/etc/containerd/config.toml` with
      `disabled_plugins = ["cri"]` already present — confirmed identical
      on all 3 nodes. This silently made the "generate default config
      (only if missing)" task a no-op everywhere (the package had already
      dropped a file), so containerd's real defaults never got a chance
      to apply. Fixed: a new idempotent task removes the
      `disabled_plugins =` line entirely (`lineinfile: state: absent`),
      notifying the same `Restart containerd` handler. Also fixed, same
      pass: two bare (deprecated, unprefixed) fact-variable usages
      (`ansible_swaptotal_mb`, `ansible_architecture`,
      `ansible_distribution_release`) flagged by a live `[DEPRECATION
      WARNING]` during the run — switched to `ansible_facts.*` form,
      matching the pattern already used correctly elsewhere in this repo.
      `ansible-lint` production profile re-verified clean after the fix.
      Re-run pending — see STATUS.md.

**Re-run result (2026-09-16): full success.** `0 failed` on all 3 nodes.
`kubeadm_prereqs` re-confirmed everything already correct (`ok`, not
`changed`) and applied the CRI fix (`changed`). `kubeadm_init` succeeded
on `cp01` — CoreDNS + kube-proxy addons applied, join token generated.
Both workers joined (`changed: [worker01]`, `changed: [worker02]`).
Verified directly with `kubectl get nodes -o wide` on `cp01`: all 3 nodes
present (`cp01` control-plane, `worker01`/`worker02`), all `v1.37.0`,
`containerd://2.3.5`, all `NotReady` — exactly as expected with no CNI
installed yet. STATUS.md and ansible/README.md updated to DEPLOYED.
