# Project Status

Last updated: 2026-09-19. Cluster state re-verified live over SSH on
2026-09-19 (`kubectl get nodes`, `kubectl get pods -A`).

State legend: **PLANNED** (designed, not built) · **IMPLEMENTED** (code/config
exists, statically validated) · **VALIDATED** (tested against a real or
representative environment) · **DEPLOYED** (running in the actual homelab).

## Current focus

Phases 1, 3 and 4 of the roadmap are done: Proxmox is bootstrapped, the Ubuntu
24.04 template is built, four VMs (`vpn01`, `cp01`, `worker01`, `worker02`)
are provisioned and hardened, and a 3-node upstream Kubernetes cluster is
initialized. Phase 4 is done too: Cilium 1.20.2 (kube-proxy replaced) and
Hubble are installed, all nodes are `Ready`, and the official connectivity
test passes. The next steps are secure remote access (Tailscale) and service
exposure. Ongoing work is a repository-quality pass — see
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
| `vpn01` (Tailscale gateway) | DEPLOYED, verified | `ansible/roles/tailscale/`, applied 2026-09-19. Tailscale 1.102.4 from the signed apt repo; joined the tailnet with a single-use tagged key (`tag:vpn`), key removed from the VM and from the controller afterwards. On the host: `BackendState: Running`, four `/32` routes advertised and auto-approved, node-key expiry off (tagged), no health warnings; a `--check` re-run reports `changed=0`. The owner confirmed from a phone outside the LAN that the lab is reachable through the tunnel (reported by the owner; which services were tried was not recorded). |
| `cp01`, `worker01`, `worker02` | DEPLOYED | Cloud-init done, hardened, joined to the cluster. |
| Guest hardening (SSH, unattended upgrades) | DEPLOYED, verified | `ansible/roles/guest_hardening/`. The `sshd_config.d/00-hardening.conf` drop-in was applied to all four VMs on 2026-09-19, one host at a time. Verified on each with a fresh connection: key login works, password and root login are refused, and `sshd -T` shows `passwordauthentication no`, `permitrootlogin no`, `maxauthtries 3`, `allowusers ubuntu`. A `--check` re-run reports `changed=0` on all four. Also covered by a container converge test in CI. No automatic reboot by design. |
| Kubernetes bootstrap (kubeadm, containerd) | DEPLOYED | `v1.37.0`, `containerd://2.3.5`; control plane and both workers `Ready`. |
| Cilium / Hubble | DEPLOYED, verified | Chart 1.20.2, `kubernetes/bootstrap/cilium/`. `kube-proxy` removed; `KubeProxyReplacement: True`; nodes `Ready`; `cilium connectivity test`: 82 tests successful, 0 failed (55 skipped, listed in the README there). Snapshots `pre-cilium` exist on the three nodes. Runs on Kubernetes 1.37, which is outside the 1.33-1.36 range upstream tests. |
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
| Management access | VPN-only (ADR-0008) | The VPN path exists, but Proxmox UI, SSH and the Kubernetes API are still reachable directly from the LAN; the Proxmox firewall has not been narrowed to the VPN yet |
| Cilium and Kubernetes versions | Inside the upstream-tested matrix | Cilium 1.20.2 lists Kubernetes 1.33-1.36; the cluster runs 1.37.0 |
| Hubble Relay TLS | Encrypted | Relay server TLS is off (in-cluster only); on the hardening list |
| Guest agent | Running in every VM | `qemu-guest-agent` is not running, so Proxmox snapshots are crash-consistent and the provider cannot read VM IPs |
| VM storage | Headroom on the thin pool | `local-lvm` is over-provisioned (thin volumes exceed pool size); no autoextend threshold |
| Proxmox API RBAC | Least privilege | Token has `PVEVMAdmin` at `/` plus scoped storage and SDN roles |
| Proxmox API TLS | Verified certificate | Provider runs with `insecure = true` for the self-signed certificate |
| Availability | Learning-grade | Single physical host, single control-plane node |
| Recovery | Documented and tested restore | No backups configured, no restore runbook yet |

## Blocked

- SOPS + age adoption needs its threat-model ADR before use.
- Self-hosted runner needs a `runner01` VM, which does not exist yet.

## Next milestone

Phase 2 — Secure remote access, remaining: make the VPN the only management
path. On a flat network this needs care (see ADR-0009): Proxmox's firewall
has a built-in "management" allowance for the local subnet that a plain rule
change does not remove, and the Kubernetes nodes have no host firewall. The
sound way to close it is network segmentation, planned as roadmap task 17;
until then the LAN stays a trusted management network. Also outstanding:
two-factor authentication on the Proxmox web UI, and confirming the router
forwards no management ports.

Then Phase 5 — Service exposure: MetalLB, Gateway API CRDs and Istio, with a
private sample app. Before any of that is published, close the flat-network
and management-access deviations above.

Anything that changes the running infrastructure follows the
destructive-action policy in [`AGENTS.md`](AGENTS.md). Work is tracked in
[`plans/`](plans/).
