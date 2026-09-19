---
title: Professionalize the homelab repository (fix CI, docs, security baseline, DR)
status: in-progress
created: 2026-09-19
updated: 2026-09-19
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
- [ ] 11. Proxmox RBAC: custom least-privilege role scoped to `/vms` (or a
  pool) instead of `PVEVMAdmin` at `/`; pin the Proxmox TLS fingerprint /
  install a real CA instead of `insecure = true`.
- [ ] 12. Declarative `kubeadm-config.yaml` (control-plane endpoint, kubelet
  serverTLSBootstrapping, encryption-at-rest config, audit policy,
  `skip-phases=addon/kube-proxy` for new clusters).
- [ ] 13. Ansible idempotence: real `changed_when` on command tasks; add
  Molecule or `--check --diff` CI job where feasible.
- [ ] 14. Tofu: VM protection (`prevent_destroy` / `protection`), disk flags
  (`discard`, `ssd`, `iothread`), `on_boot`, cloud-init snippets; encrypted
  state backup or remote backend.

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

## Resume notes

Tasks 1-10, 15, 16, 18 done; 20 partial. Backups are live (etcd timer next
fires 02:37 UTC; `homelab-daily` vzdump 03:30). Code from the tailscale role
onward is uncommitted except what was pushed as `49ded15`: the backup roles,
guest-agent role, playbooks, ADR-0012, runbook and docs are uncommitted.

The throwaway VM and the worker snapshots are gone (approved and done). The
`pre-cilium` snapshot of cp01 (VMID 102) is intentionally kept; delete it once
the owner is comfortable, since it grows on the thin pool.

Lesson worth keeping: under `--check`, `command` tasks are skipped, so a
`--check` run can never prove that drift detection works. Test idempotence
and drift with real runs on a reversible field.

Waiting on the user: `PROXMOX_VE_*` for a real `tofu plan`. Code-only work
still open: 11, 12, 13, 14; new idea: back up the OpenTofu state.

## Verification

- `gh run list` shows `validate` and `security` green on `main`.
- `make validate ALL=1` passes in WSL; `ansible-lint` passes (profile
  `production`) without `|| true`.
- `git grep -nE '192\.168\.'` returns nothing outside `*.example`.
- Docs have a single roadmap; STATUS.md matches `kubectl get nodes` and the
  Proxmox state.
- After Phase C: `kubectl get nodes` all `Ready`, `cilium status` healthy,
  restore test documented.
