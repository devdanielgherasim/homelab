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
| OpenTofu VM provisioning | DEPLOYED, verified | `Apply complete! Resources: 4 added` at rollout; on 2026-09-19 a second apply set `protection` on all four VMs (Proxmox now refuses to delete them or their disks), after a first attempt failed with 403 and was fixed (`docs/troubleshooting/tofu-apply-403-pool-allocate.md`). Boot order is set by Ansible. A fresh read-only `tofu plan` reports "No changes". State is local and not backed up (ADR-0010). |
| `vpn01` (Tailscale gateway) | DEPLOYED, verified | `ansible/roles/tailscale/`, applied 2026-09-19. Tailscale 1.102.4 from the signed apt repo; joined the tailnet with a single-use tagged key (`tag:vpn`), key removed from the VM and from the controller afterwards. On the host: `BackendState: Running`, four `/32` routes advertised and auto-approved, node-key expiry off (tagged), no health warnings; a `--check` re-run reports `changed=0`. The owner confirmed from a phone outside the LAN that the lab is reachable through the tunnel (reported by the owner; which services were tried was not recorded). |
| `cp01`, `worker01`, `worker02` | DEPLOYED | Cloud-init done, hardened, joined to the cluster. |
| Guest hardening (SSH, unattended upgrades) | DEPLOYED, verified | `ansible/roles/guest_hardening/`. The `sshd_config.d/00-hardening.conf` drop-in was applied to all four VMs on 2026-09-19, one host at a time. Verified on each with a fresh connection: key login works, password and root login are refused, and `sshd -T` shows `passwordauthentication no`, `permitrootlogin no`, `maxauthtries 3`, `allowusers ubuntu`. A `--check` re-run reports `changed=0` on all four. Also covered by a container converge test in CI. No automatic reboot by design. |
| Kubernetes bootstrap (kubeadm, containerd) | DEPLOYED | `v1.37.0`, `containerd://2.3.5`; control plane and both workers `Ready`. |
| Control-plane hardening (encryption at rest, audit log, Pod Security baseline, CIS fixes) | DEPLOYED, verified | `ansible/roles/kubeadm_init/`, `ansible/roles/kubelet_hardening/`, ADR-0013. Applied 2026-09-19 after a fresh etcd snapshot and `vzdump`; API unavailable for about 50 s while the static pods restarted. Verified independently: all 7 Secrets carry the `k8s:enc:secretbox` prefix when read from etcd, a privileged pod is refused in `default` and accepted in the exempt `kube-system`, audit log is written without Secret bodies. **CIS (kube-bench `cis-1.12`): 62 pass / 13 fail before, 76 pass / 2 fail after**; the 2 are accepted (1.2.5, 4.3.1), see `docs/security/cis-benchmark.md`. |
| Proxmox API access for OpenTofu | DEPLOYED, verified | Custom role on a resource pool instead of `PVEVMAdmin` on `/` (ADR-0011). Tested with a temporary principal over verified TLS: full VM lifecycle passes, five dangerous operations return 403. Boot order of the VMs is set by Ansible (`proxmox_vm_startup`) because OpenTofu would need `Sys.Modify` on `/` for it. TLS is verified with the cluster CA. |
| Platform bootstrap (OpenTofu) | DEPLOYED, verified on the running cluster; not yet proven from zero | ADR-0016 (Proposed), `tofu/environments/platform/`. Second stage after Ansible: Cilium and Argo CD as `helm_release`, AppProjects and root Application from Git, LoadBalancer pool from a private variable, `monitoring` namespace and generated `grafana-admin` Secret. State is local, gitignored and encrypted (OpenTofu state encryption, passphrase in `TF_ENCRYPTION`). The running cluster was adopted on 2026-09-20 with imports (10 imported, 2 added, 10 changed, 0 destroyed), the second plan is empty. **A rebuild from zero has not been run**, so reproducibility is unproven until plan task P8. The state passphrase and the state file need a backup outside this machine. |
| LoadBalancer (Cilium LB IPAM + L2) | DEPLOYED, verified | ADR-0015. Pool of 10 LAN addresses (created by the platform stage from a private variable, not in Git), `CiliumL2AnnouncementPolicy` for Services labelled `homelab.io/lb-pool: private`, workers only. Verified 2026-09-20 with a temporary Service: address assigned, Lease held by a worker, sample app reachable from the LAN. L2 announcements are Beta in Cilium 1.20; failover takes 10-20 s and one node carries an address. |
| Argo CD (GitOps) | DEPLOYED, verified | Chart 10.9.2 (v3.5.3), `kubernetes/bootstrap/argocd/`, ADR-0007 and ADR-0014. Installed 2026-09-20: 5 pods `Running`, 544 MiB of memory requests, `restricted` Pod Security. Root app-of-apps plus three AppProjects; `argocd` (self-managed), `platform` and `podinfo` reached `Synced/Healthy` from Git in 30 s. Loop verified: a manual scale-up was reverted by self-heal in 3 s and a deleted Service was recreated in 3 s. The UI is reachable only by port-forward. The admin password is now generated by the platform stage (rotated on 2026-09-20; a wrong password is refused, the new one logs in). **The old `argocd-initial-admin-secret` (stale password) still has to be deleted once by the owner.** Argo CD 3.5 lists Kubernetes 1.33-1.36 as tested; the cluster runs 1.37. |
| Cilium / Hubble | DEPLOYED, verified | Chart 1.20.2, `kubernetes/bootstrap/cilium/`. `kube-proxy` removed; `KubeProxyReplacement: True`; nodes `Ready`; `cilium connectivity test`: 82 tests successful, 0 failed (55 skipped, listed in the README there). Snapshots `pre-cilium` exist on the three nodes. Runs on Kubernetes 1.37, which is outside the 1.33-1.36 range upstream tests. |
| MetalLB | PLANNED | — |
| Istio + Gateway API | DEPLOYED, verified | ADR-0006, `kubernetes/platform/mesh/`, `kubernetes/apps/mesh-demo/`. Istio 1.31.0 in sidecar mode with `istio-cni`, Gateway API CRDs v1.6.2 (standard), installed by Argo CD. Demo app: `Gateway` of class `istio` with an address from the Cilium pool, `HTTPRoute` 90/10 (measured 187/13 in 200 requests), `PeerAuthentication` STRICT (plain traffic from an unmeshed namespace is reset, meshed traffic is `mutual_tls`). About 630 Mi of memory requests. Istio 1.31 lists Kubernetes 1.32-1.36; the cluster runs 1.37. |
| Kyverno / Trivy runtime scanning | PLANNED | Trivy config scan already runs in CI on IaC. |
| SOPS + age | PLANNED | Blocked on the public-repo threat-model ADR. |
| Prometheus / Grafana / Loki / Tempo | PLANNED | — |
| Guest agent (`qemu-guest-agent`) | DEPLOYED, verified | `ansible/roles/qemu_guest_agent/`. It had never been installed in the VMs (the template comment claiming otherwise was wrong). Now `qm agent <vmid> ping` works on all four and each VM reports its address. |
| Backups: etcd snapshot on `cp01`, Proxmox `vzdump` of `cp01` | DEPLOYED, verified | `ansible/roles/etcd_backup/`, `ansible/roles/proxmox_backup/`; scope and limits in ADR-0012. Daily verified etcd snapshot (373 keys, revision 34688, 9.4 MB) and a `vzdump` job for `cp01` (first run 50 s, 2.13 GB, agent freeze/thaw used). Restore drills passed: an etcd snapshot restored into a scratch directory (same revision and keys), and `cp01` restored into a throwaway VM without a NIC (booted, data present). Runbook: `docs/runbooks/backup-and-restore.md`. Workers and `vpn01` are deliberately not backed up. **Recovering the live cluster from a snapshot has not been exercised.** |
| Self-hosted GitHub Actions runner | PLANNED | Trust boundary designed in `docs/security/self-hosted-runners.md`; no runner exists. |

Incidents found and fixed during rollout are written up in
[`docs/troubleshooting/`](docs/troubleshooting/).

## Known deviations from the target design

Stated openly so nobody mistakes the target architecture for the current one.

| Area | Target (in `docs/architecture/`) | Today |
|---|---|---|
| Network segmentation | Separate management, node and load-balancer networks | All VMs share one flat network on `vmbr0` with the household LAN |
| Management access | VPN-only (ADR-0008) | The VPN path exists, but Proxmox UI, SSH and the Kubernetes API are still reachable directly from the LAN; the Proxmox firewall has not been narrowed to the VPN yet |
| Component versions vs Kubernetes | Inside the upstream-tested matrix | Cilium 1.20.2 and Argo CD 3.5 list Kubernetes 1.33-1.36 and Istio 1.31 lists 1.32-1.36; the cluster runs 1.37.0 |
| VM storage | Headroom on the thin pool | `local-lvm` is over-provisioned (thin volumes exceed pool size); no autoextend threshold |
| Kubelet serving certificates | CA-signed (CIS 1.2.5) | Self-signed; needs `serverTLSBootstrapping` and a CSR approver, deferred (ADR-0013) |
| Availability | Learning-grade | Single physical host, single control-plane node |
| Recovery | Off-host, tested copies | Backups exist but sit on the same disk as the VMs (ADR-0012); live-cluster recovery from an etcd snapshot is not exercised; the OpenTofu state file is not backed up |

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

Phase 5 — Service exposure is done for the private LAN (Cilium L2 load balancer, Gateway API,
Istio, a sample app). Before anything is published beyond the LAN, close the flat-network
and management-access deviations above.

Anything that changes the running infrastructure follows the
destructive-action policy in [`AGENTS.md`](AGENTS.md). Work is tracked in
[`plans/`](plans/).
