# Project Status

Last updated: 2026-09-19. Cluster state re-verified live over SSH on
2026-09-19 (`kubectl get nodes`, `kubectl get pods -A`).

State legend: **PLANNED** (designed, not built) · **IMPLEMENTED** (code/config
exists, statically validated) · **VALIDATED** (tested against a real or
representative environment) · **DEPLOYED** (running in the actual homelab).

## Current focus

Phases 1 and 3 of the roadmap are done: Proxmox is bootstrapped, the Ubuntu
24.04 template is built, four VMs (`vpn01`, `cp01`, `worker01`, `worker02`)
are provisioned and hardened, and a 3-node upstream Kubernetes cluster is
initialized. The nodes are `NotReady` and CoreDNS is `Pending` because no CNI
is installed yet. Phase 4 (Cilium + Hubble) is next. The current
work item is a repository-quality pass — see
[`plans/2026-09-19-professionalize-repo.md`](plans/2026-09-19-professionalize-repo.md).

The roadmap and its numbering live in one place:
[`docs/architecture/overview.md`](docs/architecture/overview.md#6-implementation-roadmap).

## Component status

| Component | State | Evidence / notes |
|---|---|---|
| Repository structure, docs, ADRs | IMPLEMENTED | ADR set in `docs/adr/`. |
| CI (`validate`, `security`) | IMPLEMENTED | GitHub-hosted runners only. `validate` was red from the first run until 2026-09-19; after the fixes both `validate` and `security` pass on `main` (verified on the runner, including the `ansible-converge` job that applies roles in a throwaway container). `main` requires those status checks; direct pushes by the owner are still allowed and PRs are not yet required. |
| Proxmox host (VE 9.2) | DEPLOYED | Physically installed, configured by Ansible. |
| Proxmox bootstrap: network check, API token, SSH key, firewall, key-only SSH | DEPLOYED | `ansible/roles/proxmox_bootstrap/`. All six stages run against the host; key-only SSH confirmed from a fresh session after lockdown. |
| Ubuntu 24.04 cloud-init template (VMID 9000) | DEPLOYED | `ansible/roles/proxmox_template/`. `qm config 9000` shows `template: 1`, disk and cloud-init drive attached, agent enabled. |
| OpenTofu VM provisioning | DEPLOYED | `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` All four VMs reachable (ping, SSH, `cloud-init status: done`). |
| `vpn01` (Tailscale gateway) | DEPLOYED (VM only) | VM exists and is hardened. **Tailscale is not configured yet**; it does not act as a gateway. |
| `cp01`, `worker01`, `worker02` | DEPLOYED | Cloud-init done, hardened, joined to the cluster. |
| Guest hardening (SSH, unattended upgrades) | DEPLOYED, verified | `ansible/roles/guest_hardening/`. The `sshd_config.d/00-hardening.conf` drop-in was applied to all four VMs on 2026-09-19, one host at a time. Verified on each with a fresh connection: key login works, password and root login are refused, and `sshd -T` shows `passwordauthentication no`, `permitrootlogin no`, `maxauthtries 3`, `allowusers ubuntu`. A `--check` re-run reports `changed=0` on all four. Also covered by a container converge test in CI. No automatic reboot by design. |
| Kubernetes bootstrap (kubeadm, containerd) | DEPLOYED | `v1.37.0`, `containerd://2.3.5`. Live check 2026-09-19: three nodes present, all `NotReady`; control-plane static pods `Running`; `kube-proxy` still present. |
| Cilium / Hubble | PLANNED | Next milestone. |
| MetalLB | PLANNED | — |
| Istio + Gateway API | PLANNED | — |
| Argo CD | PLANNED | — |
| Kyverno / Trivy runtime scanning | PLANNED | Trivy config scan already runs in CI on IaC. |
| SOPS + age | PLANNED | Blocked on the public-repo threat-model ADR. |
| Prometheus / Grafana / Loki / Tempo | PLANNED | — |
| Backups (Proxmox `vzdump`, etcd snapshots) | PLANNED | Not configured. Until they exist the lab is recoverable only by rebuilding from Git. |
| Self-hosted GitHub Actions runner | PLANNED | Trust boundary designed in `docs/security/self-hosted-runners.md`; no runner exists. |

Incidents found and fixed during rollout are written up in
[`docs/troubleshooting/`](docs/troubleshooting/).

## Known deviations from the target design

Stated openly so nobody mistakes the target architecture for the current one.

| Area | Target (in `docs/architecture/`) | Today |
|---|---|---|
| Network segmentation | Separate management, node and load-balancer networks | All VMs share one flat network on `vmbr0` with the household LAN |
| Management access | VPN-only (ADR-0008) | Proxmox UI, SSH and the Kubernetes API are reachable from the LAN; Tailscale not configured |
| Pod networking | Cilium with kube-proxy replacement | No CNI; default `kube-proxy` still deployed |
| Proxmox API RBAC | Least privilege | Token has `PVEVMAdmin` at `/` plus scoped storage and SDN roles |
| Proxmox API TLS | Verified certificate | Provider runs with `insecure = true` for the self-signed certificate |
| Availability | Learning-grade | Single physical host, single control-plane node |
| Recovery | Documented and tested restore | No backups configured, no restore runbook yet |

## Blocked

- SOPS + age adoption needs its threat-model ADR before use.
- Self-hosted runner needs a `runner01` VM, which does not exist yet.

## Next milestone

Phase 4 — Cluster networking:

1. Remove the `kube-proxy` DaemonSet, install Cilium and Hubble, and confirm
   the nodes turn `Ready` (see `docs/architecture/kubernetes.md`).
2. Run the Cilium connectivity test and record the result.

In parallel, Phase 2 — Secure remote access: install and configure Tailscale
on `vpn01` and advertise the node network (see
`docs/architecture/networking.md`). Not blocking phase 4.

Anything that changes the running infrastructure follows the
destructive-action policy in [`AGENTS.md`](AGENTS.md). Work is tracked in
[`plans/`](plans/).
