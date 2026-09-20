---
title: Professionalize the homelab repository (fix CI, docs, security baseline, DR)
status: in-progress
created: 2026-09-19
updated: 2026-09-20
---

# Professionalize the homelab repository

## Context

A review on 2026-09-19 found the homelab works (Proxmox + 4 VMs + 3-node
kubeadm cluster `v1.37.0`, all nodes `NotReady` pending a CNI — confirmed
live over SSH on 2026-09-19) but the repository does not yet look like
production work. The goal is a portfolio that shows production-grade
configuration, not learning basics.

Findings driving this plan:

- CI `validate` has been red since the first run: `ansible-playbook
  --syntax-check` runs from the repo root so `ansible/ansible.cfg`
  (`roles_path`) is not read; markdownlint fails (mostly MD060 table style,
  plus MD032/MD034/MD038/MD040); `tofu fmt -check` inside `find -exec ... \;`
  can never fail the job; `ansible-lint || true`; kubeconform is downloaded
  from `releases/latest` without a checksum.
- Docs contradict each other and STATUS.md (AGENTS.md / README / session hook
  say "no infrastructure provisioned"; `infrastructure.md` and
  `kubernetes.md` say tofu/ansible hold only a README; phase numbering in
  `overview.md` differs from STATUS.md).
- STATUS.md (tracked, public) lists the real LAN IPs and CIDR, which AGENTS.md
  forbids.
- All 8 ADRs are still `Proposed`; ADRs for the flat network, kubeadm
  configuration and Proxmox RBAC scope are missing.
- Guest SSH hardening edits `sshd_config` with `lineinfile`, which a
  `sshd_config.d/*.conf` drop-in can override; never checked with `sshd -T`.
- Cluster hardening/DR gaps: no `kubeadm-config.yaml`, no control-plane
  endpoint, kube-proxy still present although Cilium replaces it, no
  encryption at rest, no audit policy, no etcd snapshot, no `vzdump`
  backups, no restore runbook; Proxmox RBAC granted at `/` while described
  as least-privilege; provider uses `insecure = true`.
- `plans/2026-09-16-ai-cli-orchestrator.md` and `docs/superpowers/` belong to
  a different project and dilute the portfolio story.

Decisions: work on `main` locally but commit in small focused commits only
when the user asks (AGENTS.md / global preferences). Anything that touches
the real infrastructure (kubectl against the cluster, `tofu apply`, Ansible
against hosts, Proxmox changes) needs explicit approval per AGENTS.md's
destructive-action policy, with impact / rollback / downtime stated first.
Correction to the review: switching to Cilium kube-proxy replacement does NOT
require rebuilding the cluster — deleting the `kube-proxy` DaemonSet and
ConfigMap and flushing its iptables rules is the documented path.

Tools: the Ansible/OpenTofu toolchain lives in WSL Ubuntu-24.04
(`wsl -d Ubuntu-24.04 -- bash -lc ...`), not in Git Bash. The admin SSH key
is `~/.ssh/homelab_admin_ed25519` inside that WSL distro.

## Tasks

### Phase A — repository quality (no infrastructure changes)

- [x] 1. Fix CI `validate`: run ansible syntax-check with `ANSIBLE_CONFIG`
  pointing at `ansible/ansible.cfg` (or `cd ansible`); make `tofu fmt -check`
  actually fail; drop `|| true` on ansible-lint; pin kubeconform to a version
  and verify its checksum.
  - files: `.github/workflows/validate.yml`
- [x] 2. Fix markdownlint: disable MD060 in `.markdownlint.jsonc` (stylistic,
  noisy) and fix real findings MD032/MD034/MD038/MD040 in the affected files.
- [x] 3. Make ansible-lint pass at `production` profile locally (WSL) so the
  gate can be blocking; fix yamllint line-length findings.
- [x] 4. Sync docs with reality: AGENTS.md, README.md, `troubleshooting/README.md`,
  `infrastructure.md`, `kubernetes.md`, session-brief hook, phase numbering
  (one canonical roadmap), architecture docs flag what is built vs designed.
- [x] 5. Remove real LAN identifiers from tracked files (STATUS.md), keep them
  only in gitignored/`local/` files; make gitleaks/CI check for
  `192.168.` in tracked files outside `*.example`.
- [x] 6. ADRs: 0001-0004 marked `Accepted` (implemented); 0005-0008 stay
  `Proposed` until built. Added ADR-0009 (flat network), 0010 (local state),
  0011 (Proxmox token privileges). The kubeadm-config ADR comes with task 12.
- [x] 7. Move the AI-orchestrator plan/spec out of this repo (or into a
  clearly separated `docs/contributing/` note) and add `.mcp.json` to
  `.gitignore`.
- [x] 8. Dependabot: add `terraform` ecosystem for tofu providers and `pip`
  for CI pins; pin GitHub Actions to commit SHAs (verified via `gh api`).
- [x] 9. Add README badges (CI status), current-state diagram/table and a
  "what is built" section derived from STATUS.md.

### Phase B — hardening as code (review, then apply with approval)

- [x] 10. Guest SSH hardening via `sshd_config.d/00-hardening.conf` drop-in,
  verified with `sshd -T`.
  - Code + container converge test + CI job `ansible-converge` (green on the
    GitHub runner).
  - APPLIED 2026-09-19 with user approval: `--check --diff` first, then
    worker02, worker01, cp01, vpn01 one at a time, each verified from a fresh
    SSH connection (key login ok; password and root login refused). `--check`
    re-run: `changed=0` on all four. The role was also made safe under
    `--check` (read-only `sshd -t`/`-T` run with `check_mode: false`; the
    effective-config assertion is skipped in check mode).
  - Deliberately not added: ufw (would fight Cilium's datapath), fail2ban
    (key-only SSH).
- [x] 11. Proxmox RBAC: custom least-privilege role scoped to `/vms` (or a
  pool) instead of `PVEVMAdmin` at `/`; pin the Proxmox TLS fingerprint /
  install a real CA instead of `insecure = true`.
- [x] 12. Declarative `kubeadm-config.yaml` (control-plane endpoint, kubelet
  serverTLSBootstrapping, encryption-at-rest config, audit policy,
  `skip-phases=addon/kube-proxy` for new clusters).
- [x] 13. Ansible idempotence: real `changed_when` on command tasks; add
  Molecule or `--check --diff` CI job where feasible.
- [x] 14. Tofu hardening: VM `protection`, `on_boot`, `reboot_after_update = false`,
  pool scope, TLS verified.
  - DONE 2026-09-19: applied by the owner after a first apply failed with 403
    (fixed with `Pool.Audit`; boot order moved to Ansible because it needs
    `Sys.Modify`). Verified: `protection: 1` on all four VMs, fresh plan
    "No changes".
  - NOT done on purpose: disk flags `discard`/`ssd` (may need a reboot; take them
    in a reboot window, they would also let the thin pool reclaim space); a
    backup of the local OpenTofu state.

### Phase C — platform roadmap (each step needs explicit approval to apply)

- [x] 15. Cilium + Hubble install: remove kube-proxy DaemonSet/ConfigMap,
  install Cilium with `kubeProxyReplacement=true`, nodes `Ready`, run the
  Cilium connectivity test.
  - DONE 2026-09-19 with user approval. Proxmox snapshots `pre-cilium` on
    102/103/104 first; chart 1.20.2; values in
    `kubernetes/bootstrap/cilium/values.yaml` (no IPs; `k8sServiceHost` is
    passed with `--set`). Result: nodes `Ready`, `KubeProxyReplacement: True`,
    connectivity test 82 tests / 707 actions successful, 0 failed.
  - Deviation recorded: Cilium 1.20.2 is not upstream-tested on Kubernetes
    1.37. Follow-ups: Hubble Relay server TLS; delete the `pre-cilium`
    snapshots once satisfied (they grow on a thin pool that is already
    over-provisioned).
- [ ] 16. Tailscale on `vpn01` + subnet router; then restrict Proxmox UI / API
  to the VPN.
  - DONE 2026-09-19: role `ansible/roles/tailscale`, playbook, inventory group
    `vpn_gateway`, container test (`scripts/test-roles.sh`, both roles), applied
    to `vpn01`. Joined the tailnet with a single-use `tag:vpn` key read from a
    root-only file (`TS_AUTHKEY_FILE`); the key is removed from the VM by the
    role and the controller-side file was deleted. Verified on the host:
    Running, four /32 routes advertised and auto-approved, `--check` re-run
    `changed=0`.
  - Bug found and fixed by the container test: after adding a repo the apt
    cache must be refreshed even if it is recent.
  - Client check: the owner confirmed from a phone outside the LAN that it
    works (2026-09-19).
  - DEFERRED, needs design (not a one-line change): making the VPN the only
    management path. Proxmox allows the local subnet to reach 8006/22 through
    a built-in management ipset even under policy_in DROP, so narrowing
    `proxmox_bootstrap_firewall_allowed_mgmt_cidrs` alone does not close the
    LAN; the cluster-level `management` ipset would need to be set, and the
    Kubernetes nodes have no host firewall. Segmentation (task 17) is the
    right fix. Verify the Proxmox behaviour against the PVE firewall docs
    before implementing. Caveat: on the home LAN, clients that accept the /32
    routes may hairpin through vpn01.
  - Also open: TOTP two-factor on the Proxmox web UI (manual, in the UI) and
    checking that the router forwards no management ports (manual).
- [ ] 17. Network segmentation (VLAN or bridges) per `networking.md`.
- [x] 18. DR: etcd snapshot timer, Proxmox `vzdump` schedule, a tested
  restore, and the runbook that comes from it.
  - DONE 2026-09-19 with user approval. Scope decided with the owner: backups
    stay on the Proxmox host (ADR-0012) and cover only etcd + `cp01`; the
    workers and `vpn01` are disposable and are not backed up.
  - Roles: `etcd_backup` (etcdctl/etcdutl 3.7.0 with checksum, systemd
    timer, script with retention and verification, tested against stand-ins
    in `scripts/test-roles.sh`), `proxmox_backup` (pvesh job, idempotence
    verified end to end after a real bug: pvesh returns `prune-backups` as a
    mapping; `--check` skips `command` tasks so it cannot prove drift
    detection), `qemu_guest_agent` (was missing from every VM).
  - Drills passed: etcd restore into scratch dir (revision 34688, 373 keys,
    live etcd untouched); cp01 restored from vzdump into VMID 9100 with no
    NIC, booted, data present.
  - NOT done: recovering the live cluster from a snapshot; backing up the
    OpenTofu state; copying backups off the host (declined by the owner).
  - Cleanup done with the owner's approval: throwaway VM 9100 destroyed
    (guarded: only if named cp01-restore-test and stopped); `pre-cilium`
    snapshots on VMs 103 and 104 deleted; 102's kept as a rollback point.
- [ ] 19. MetalLB, Gateway API + Istio, Argo CD (GitOps), Kyverno, cert-manager,
  observability — each with an ADR/doc update and STATUS.md change.
- [ ] 20. Workflow: PRs with required status checks on `main`, signed commits.
  - DONE 2026-09-19: required status checks set on `main` via the API
    (`changes`, `tofu`, `ansible`, `ansible-converge`, `kubernetes`, `shell`,
    `docs`, `gitleaks`, `topology-guard`); `enforce_admins` left off so the
    owner can still push directly.
  - PENDING: require pull requests, signed commits, `enforce_admins`.

## Hardening sub-plan (started 2026-09-19, owner said "finish the hardening")

Baseline measured with kube-bench 0.16.0, benchmark cis-1.12, on cp01:
62 pass, 13 fail, 56 warn (manual). Target: fix what is fixable, document the
rest as accepted. Accepted on purpose: 1.2.5 (needs serverTLSBootstrapping and
a CSR approver, one more component; revisit with GitOps) and 4.3.1 (checks
kube-proxy, which Cilium replaced).

- [x] H1. `kubeadm_init` becomes the single source of truth: renders
  `kubeadm-config.yaml` (v1beta4, based on the live ClusterConfiguration),
  encryption-at-rest (secretbox, key generated on the node, never in Git),
  audit policy, Pod Security admission defaults (baseline enforce, restricted
  warn/audit, kube-system exempt), profiling off; used by `kubeadm init
  --config` for rebuilds and reconciled onto the live control plane with
  `kubeadm init phase control-plane all`. The etcd backup archive must also
  contain the encryption config or restored data cannot be read.
- [x] H2. `kubelet_hardening` role: file modes for CIS 4.1.x on all nodes.
- [x] H3. etcd data directory owned by an `etcd` user (CIS 1.1.12).
- [x] H4. Apply to the live cluster with the owner's approval: fresh etcd
  snapshot and vzdump of cp01 first, manifests backed up, apiserver restarts
  for a short time. Verify: secrets carry the `k8s:enc:secretbox` prefix in
  etcd, audit log is written, a privileged pod is refused by server-side dry
  run, kube-bench re-run.
- [x] H5. Hubble Relay server TLS (Helm upgrade, with approval).
- [x] H6. Proxmox: verify TLS with the cluster CA instead of `insecure = true`;
  narrow the token to a resource pool / custom role (task 11). Test with a
  temporary principal, never the real token secret.
- [~] H7. OpenTofu: read-only plan with a temporary token; only then propose
  protection / on_boot / startup order / discard changes (task 14). Any
  apply needs approval.
- [x] H8. Docs: ADR-0013 (control-plane hardening choices and accepted
  deviations), `docs/security/cis-benchmark.md` with before/after, STATUS.

Status of the sub-plan (legend: [~] = code written, validated, NOT yet applied):
H1-H3 (`kubeadm_init` config/reconcile, `kubelet_hardening`, etcd user), H5
(Hubble Relay TLS values), H6 (RBAC role/pool + CA fetch in
`proxmox_bootstrap`) and H7 (`pool_id`, `protection`, `on_boot`, startup order
in the tofu module; `proxmox_insecure` default false) are written and pass
ansible-lint, tofu validate, the converge tests, and read-only dry-runs against
the real hosts (kubeadm config validate + a control-plane dry-run showing only
added flags). Nothing has been applied. H4 and the applies of H5/H6/H7 need the
owner's approval with impact and rollback stated.

## Scaling roadmap (owner's goal, 2026-09-20)

Goal: more workers, including two Hyper-V VMs on the owner's Windows PC, and an
Azure-like way to scale by hand or automatically, with things to look at.
Owner's PC: 32 GB RAM, Ryzen 7 5700G, on only while working; prefers Hyper-V.
Order: (1) `for_each` worker pool + generated inventory [in progress];
(2) observability and Argo CD; (3) Hyper-V workers with labels and taints (the PC
is not always on, so nothing critical may depend on them); (4) HPA/KEDA on a demo
app; (5) node autoscaling, preferably a "warm pool" (pre-created VMs powered on and
off) or Cluster API, to be evaluated; (6) a small control panel.

- [~] S1. `workers` map + `for_each` + `moved` blocks; `nodes` output;
  `tofu_inventory.py`; Ansible roles derive pool VMIDs and boot order from the
  inventory. Code done and validated: a read-only plan shows 0 add / 0 change /
  0 destroy and only the two state moves; the dynamic inventory matches the static
  one (groups, addresses, derived values, `changed=0`). NOT applied: the state
  move and the new outputs need one apply (state only) with the owner's approval;
  then switch the local `hosts.yml` to the Proxmox host only and point Ansible at
  `inventories/production/`. A runbook for adding/removing a worker is written
  after that has been done once (2 -> 3 -> 2).

## Platform build (started 2026-09-20)

Capacity measured 2026-09-20: each worker has about 2.5 GB free (2 vCPU, under 15%
used); the Proxmox host has about 4.9 GB available. So the platform has roughly 5 GB
of RAM in total and every component needs an explicit budget. No StorageClass exists.
Approach: three read-only research agents in parallel (Argo CD; load balancer +
Gateway API + Istio; observability), then implementation in disjoint directories,
then one integration pass here. Nothing is applied to the cluster without approval.

- [x] G1. Argo CD (GitOps): bootstrap install from `kubernetes/bootstrap/argocd/`,
  root app-of-apps under `kubernetes/platform/`, Cilium stays bootstrap-managed
  (a CNI managed by the tool that runs on it can lock itself out), CRD-aware
  kubeconform in CI, ADR, sample app synced from Git, self-heal demonstrated.
  - DONE 2026-09-20 with the owner's approval: commit `d1adfad` (CI green), then
    namespace, `helm install`, three AppProjects and the root app. `argocd`,
    `platform`, `podinfo` synced in 30 s; self-heal reverted a manual change in 3 s.
    Lesson: memory requests came to 544 MiB, not the ~350 first estimated.
  - Open: the owner must rotate the initial admin password and delete
    `argocd-initial-admin-secret`. The `projects` Application (added afterwards) puts
    the AppProjects under GitOps too.

- [x] G2. Load balancer (Cilium LB IPAM + L2, ADR-0015) and the Gateway API CRDs.
  - DONE 2026-09-20 with the owner's approval: `helm upgrade` cilium (revision 3),
    pool from the private inventory (`ansible/roles/cilium_lb_pool`, idempotent),
    policy applied, temporary Service got an address and answered from the LAN.
    Lesson: agents need `rollout restart` after the ConfigMap change (see ADR-0015).
  - Open: push the policy Application (`cilium-l2`) so Argo CD owns it; the Gateway
    API CRDs come with the G3 Applications.
- [x] G3. Istio + Gateway API gateway, a sample app with weighted routing, mTLS,
  private access only. cert-manager not needed yet (HTTP listener, no TLS termination).
  - DONE 2026-09-20 in three verified steps, each pushed with approval: Gateway API CRDs
    (`3e305ce`), Istio (`73a422f`), `mesh-demo` (`f5c788b`, then fixes `034873e` and
    `c7d2b3c`). Verified: injection on both workers under baseline, 187/13 split,
    STRICT rejects plain traffic, meshed traffic `mutual_tls`. All 10 Applications
    `Synced/Healthy`.
  - Lessons: the agent-written demo manifests had two bugs no offline validator sees
    (`args` without `command` replaced the image CMD; HTTPRoute defaults missing, so the
    Application stayed OutOfSync). Test agent output on the cluster before pushing.
- [ ] G4. Observability (Prometheus + Grafana, Hubble metrics, capacity dashboards
  for later autoscaling), logs only if they fit in RAM, storage decision without a
  StorageClass.
  - Pushed `d5a4c71`: stack Synced; Prometheus, operator, kube-state-metrics and the
    three node-exporters run. Grafana sidecars were OOMKilled at 64Mi; fix (128Mi
    limit, README budget 708Mi) is local, not pushed. The `monitoring` namespace and
    the `grafana-admin` Secret were created BY HAND: to be replaced by task P4.
  - Open: verify targets/rules/dashboard, Cilium and Hubble metrics.
- [ ] G5. Kyverno policies and Trivy operator (if RAM allows), NetworkPolicies
  default-deny per namespace.

### P. Bootstrap as code (owner's requirement, 2026-09-20)

"No manual steps in the bootstrap; everything in Git and reproducible from zero."
Design in ADR-0016: a second OpenTofu stage, `tofu/environments/platform`, with the
helm, kubernetes, kubectl and random providers, run after Ansible has built the cluster.

- [ ] P1. ADR-0016 and this plan (done when both are in Git).
- [ ] P2. Kubeconfig without hand-copying: Ansible playbook that fetches
  `admin.conf` to a private local path (mode 0600, gitignored).
- [x] P3. Skeleton `tofu/environments/platform`: provider pins from a real `tofu init`,
  encrypted state (`TF_ENCRYPTION`), `.example` tfvars, CI validate passes.
- [x] P4. Resources: Cilium (`helm_release`), namespaces, Argo CD (`helm_release`,
  chart version read from `platform/apps/argocd.yaml`, generated admin password),
  AppProjects and root Application from the existing YAML files, LB pool from private
  tfvars, `monitoring` namespace and `grafana-admin` Secret (`random_password`).
- [x] P5. Adopt the running cluster: `tofu import`, then a plan that shows only the
  expected differences; apply with the owner's approval (Argo CD admin password is
  rotated by this apply, Grafana Secret is recreated).
  - DONE 2026-09-20 with the owner's approval: `Apply complete! 10 imported, 2 added,
    10 changed, 0 destroyed`. Cilium revision 4, Argo CD revision 2, nodes `Ready`, all
    Applications `Synced/Healthy`, no agent restart. New Argo CD password logs in (HTTP
    200), a wrong one is refused (401); `grafana-admin` equals the tofu output; the state
    file is encrypted (no plaintext password markers). Idempotence: the plan is empty,
    also after Argo CD refreshes the root Application (needs `ignore_changes` on
    `yaml_incluster` for that object, see the comment in `argocd.tf`).
  - My summary before the apply said "5 import / 5 change"; the real numbers were 10 / 10
    (the first, failed plan had not included the `kubectl` objects). The apply guard
    caught it and I re-checked the full diff before going on.
  - `imports.tf` deleted after the apply: an `import` block for a missing object fails,
    which would break a bootstrap from zero.
  - Leftover of the manual install: `argocd-initial-admin-secret` (stale password) still
    exists. A fresh bootstrap never creates it.
  - Private inputs (`terraform.tfvars`, state passphrase in `~/.tofu-platform-passphrase`
    in WSL) exist locally; the passphrase must be copied to a password manager.
  - Playbook `k8s-kubeconfig.yml` (P2) is written and lint-clean, not yet run.
- [x] P6. Remove the manual paths: Ansible role `cilium_lb_pool`, the `kubectl`/`helm`
  install steps in the READMEs, `CreateNamespace` for `monitoring` in the Application;
  update ADR-0014, STATUS, runbook.
  - DONE 2026-09-20 (local, not pushed yet): role, playbook and variable example deleted;
    Cilium and Argo CD READMEs, ADR-0014/0015, gitops.md, kubernetes/README.md and the
    comments in the manifests now point to the platform stage; STATUS has a row for it.
    No runbook yet: write it after the from-zero proof (P8), when the steps are known.
- [ ] P7. One entry point (`make bootstrap` or a script) that chains tofu VMs, Ansible,
  kubeconfig, tofu platform.
- [ ] P8. Proof from zero: rebuild the cluster VMs and run the chain end to end. Needs
  the owner's explicit approval (destroys and recreates the running cluster; etcd
  backups exist; expected downtime a few hours).

## Resume notes

Hardening applied 2026-09-19 with the owner's approval (A control plane, B Hubble
TLS, C Proxmox RBAC, D tofu plan): CIS 62/13 -> 76/2, Secrets encrypted, audit
log and Pod Security on, Hubble Relay TLS on (relay and UI verified), Proxmox
token moved from PVEVMAdmin on `/` to a 13-privilege role on the `homelab` pool
(15/15 API checks incl. 5 refused operations), TLS verified with the cluster CA.

The owner applied OpenTofu on 2026-09-19 (after a first 403, fixed): protection
on all four VMs, boot order via Ansible, fresh plan "No changes". Still open:
disk flags in a reboot window; back up the OpenTofu state; task 17 network
segmentation; task 19 platform components (Argo CD, MetalLB, Gateway API + Istio,
observability); task 20 PRs and signed commits.

Uncommitted: everything from the hardening work. Two hook false positives blocked
plain-text edits that only mentioned destructive commands; they were written with
the file tools instead of the shell.

## Verification

- `gh run list` shows `validate` and `security` green on `main`.
- `make validate ALL=1` passes in WSL; `ansible-lint` passes (profile
  `production`) without `|| true`.
- `git grep -nE '192\.168\.'` returns nothing outside `*.example`.
- Docs have a single roadmap; STATUS.md matches `kubectl get nodes` and the
  Proxmox state.
- After Phase C: `kubectl get nodes` all `Ready`, `cilium status` healthy,
  restore test documented.
