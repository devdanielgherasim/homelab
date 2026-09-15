# Project Status

Last updated: 2026-09-16 (kubeadm bootstrap role generated, not yet run).

State legend: **PLANNED** (designed, not built) · **IMPLEMENTED** (code/config
exists, statically validated) · **VALIDATED** (tested against a real or
representative environment) · **DEPLOYED** (running in the actual homelab).

## Current focus

Phase 1 (Foundation) is done: Proxmox host bootstrapped, Ubuntu 24.04
template built, all 4 VMs (`vpn01`, `cp01`, `worker01`, `worker02`)
created, hardened, and verified. Moving into Kubernetes bootstrap.

## Component status

| Component | State | Notes |
|---|---|---|
| Repository structure / docs / CI | IMPLEMENTED | This bootstrap. |
| Architecture design | PLANNED | `docs/architecture/`, ported from prior design doc. |
| Proxmox host | DEPLOYED | Physically installed (Proxmox VE 9.2), under Ansible-managed configuration, now hosting 4 provisioned VMs (see below). |
| Proxmox bootstrap (network check, API token, SSH key, firewall) | DEPLOYED | `ansible/roles/proxmox_bootstrap/`, all 6 stages run against `pve01` by the user and verified: dedicated OpenTofu API token created, admin SSH key added, firewall rules applied, SSH password auth disabled — confirmed by a direct key-only SSH test after lockdown. One real bug found and fixed mid-rollout: `template` can't write directly to `/etc/pve` (pmxcfs, non-POSIX — worked around with stage-to-`/tmp`-then-`cp`); a fragile `regex_replace`-derived private-key path silently pointed at the `.pub` file instead (replaced with an explicit variable). See `plans/2026-09-15-proxmox-bootstrap-role.md`. |
| Proxmox VM template (Ubuntu 24.04 cloud-init, VMID 9000) | DEPLOYED | `ansible/roles/proxmox_template/` run against `pve01`; `qm config 9000` confirmed complete (`template: 1`, disk + cloud-init drive attached, agent enabled). |
| `vpn01` (Tailscale gateway) | DEPLOYED | VMID 101, `192.168.1.50`. Cloud-init `status: done`, hardened (see below), SSH verified with the admin key. Tailscale itself not yet configured — VM exists, gateway role not yet set up. |
| `cp01` | DEPLOYED | VMID 102, `192.168.1.51`. Cloud-init `status: done`, hardened. Kubernetes not yet installed on it (role ready — see below). |
| `worker01` / `worker02` | DEPLOYED | VMIDs 103/104, `192.168.1.52`/`.53`. Cloud-init `status: done` on both, hardened. Kubernetes not yet installed (role ready). |
| Guest OS hardening (SSH defense-in-depth, unattended-upgrades) | DEPLOYED | `ansible/roles/guest_hardening/` run against all 4 VMs — `0 failed`, `4 changed` each. Spot-verified on `vpn01`: `PasswordAuthentication no` active, sshd restarted and reachable, `unattended-upgrades` installed. No automatic reboot (deliberate default). |
| OpenTofu Proxmox provisioning | DEPLOYED | `tofu apply` run against `pve01` — `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` All 4 VMs verified reachable (ping + SSH + `cloud-init status`). Non-fatal QEMU-agent IP-report timeout warning during apply, confirmed cosmetic (SSH access unaffected). Three real Proxmox RBAC gaps found and fixed during rollout — `PVEVMAdmin` alone isn't enough for a clone: also needed `PVEDatastoreUser` on `/storage/local-lvm` (`Datastore.AllocateSpace`) and `PVESDNUser` on `/sdn/zones/localnetwork` (`SDN.Use`, a PVE 9-specific check), each granted to both the user and the token (API tokens with `--privsep 1` need ACLs on the token principal, not just the user — the two are intersected, not unioned). See `ansible/roles/proxmox_bootstrap/tasks/api_token.yml` and `plans/2026-09-15-vm-provisioning.md`. |
| Ansible node configuration | IMPLEMENTED | `ansible/` has `proxmox_bootstrap`, `proxmox_template`, `guest_hardening` (all deployed) plus `kubeadm_prereqs`/`kubeadm_init`/`kubeadm_join` (generated, validated, not yet run). |
| Kubernetes bootstrap (kubeadm) | IMPLEMENTED | `ansible/roles/kubeadm_prereqs`\`kubeadm_init`\`kubeadm_join` + `playbooks/k8s-bootstrap.yml` — containerd (Docker apt repo, systemd cgroup), kubeadm/kubelet/kubectl v1.37 from `pkgs.k8s.io`, versions held via `dpkg_selections`. `ansible-lint` (production profile) and `--syntax-check` pass. **Not yet applied.** Nodes will show `NotReady` until Cilium is installed — expected. See `plans/2026-09-16-kubeadm-bootstrap.md`. |
| Cilium / Hubble | PLANNED | — |
| MetalLB | PLANNED | — |
| Istio + Gateway API | PLANNED | — |
| Argo CD | PLANNED | — |
| Kyverno / Trivy runtime scanning | PLANNED | Trivy config-scan already runs in CI on IaC. |
| SOPS + age | PLANNED | Blocked on public-repo threat-model review (ADR pending). |
| Prometheus / Grafana / Loki / Tempo | PLANNED | — |
| Self-hosted GitHub Actions runner | PLANNED | Trust boundary designed (`docs/security/self-hosted-runners.md`); no runner configured. |

## Blocked

- SOPS + age adoption — needs its threat-model ADR before use.
- Self-hosted runner — needs `runner01` VM to exist first (depends on Phase 1 provisioning).

## Roadmap

See `docs/architecture/overview.md` §Implementation Roadmap for the full
9-phase build plan (Foundation → Remote access → Kubernetes bootstrap →
Cluster networking → Service exposure → GitOps → Security controls →
Observability → Automation).

## Next milestone

Phase 1 — Foundation: **done** (2026-09-16). Proxmox bootstrapped,
template built, all 4 VMs deployed, guest-hardened, and verified.

Phase 2/3 — Kubernetes bootstrap + remote access, next:

1. **Human action**: run `playbooks/k8s-bootstrap.yml` against
   `cp01`/`worker01`/`worker02` — role is written and validated, not yet
   applied.
2. Install Cilium (nodes will be `NotReady` until then).
3. `vpn01`: install and configure Tailscale, advertise the
   `192.168.1.0/24` subnet — see `docs/architecture/networking.md`. Not
   blocking steps 1-2 (LAN access already works for building/testing).

Tracked in `plans/`.
