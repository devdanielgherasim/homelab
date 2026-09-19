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

- [ ] 10. Guest SSH hardening via `sshd_config.d/00-hardening.conf` drop-in,
  verified with `sshd -T`.
  - DONE (code + test): role rewritten (`templates/sshd_00-hardening.conf.j2`,
    handler, lock-out guard, `sshd -T` assertion); `scripts/test-guest-hardening.sh`
    proves it beats a cloud-init override, is idempotent, and refuses a
    lock-out allow-list; CI job `ansible-converge` added.
  - PENDING: apply to the four real VMs (needs user approval — it changes
    remote-access rules; rollback is deleting the drop-in over the still-open
    SSH session or the Proxmox console). Deliberately not added: ufw (would
    fight Cilium's datapath), fail2ban (key-only SSH).
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

- [ ] 15. Cilium + Hubble install: remove kube-proxy DaemonSet/ConfigMap,
  install Cilium with `kubeProxyReplacement=true`, nodes `Ready`, run the
  Cilium connectivity test.
- [ ] 16. Tailscale on `vpn01` + subnet router; then restrict Proxmox UI / API
  to the VPN.
- [ ] 17. Network segmentation (VLAN or bridges) per `networking.md`.
- [ ] 18. DR: etcd snapshot CronJob/systemd timer, Proxmox `vzdump` schedule,
  a tested restore, and the `docs/runbooks/` entries that come from it.
- [ ] 19. MetalLB, Gateway API + Istio, Argo CD (GitOps), Kyverno, cert-manager,
  observability — each with an ADR/doc update and STATUS.md change.
- [ ] 20. Workflow: PRs with required status checks on `main`, signed commits.

## Resume notes

Phase A (tasks 1-9) done locally; task 10 code and container test done.
Everything is uncommitted and unpushed. Verified in WSL Ubuntu-24.04 (mise
shims on PATH; run a script through `wsl -d Ubuntu-24.04 -- bash <script>`
from the PowerShell tool) and Docker (from Git Bash): ansible-lint production
profile, `tofu fmt -check`, yamllint, markdownlint, gitleaks, shellcheck, the
topology guard, and `scripts/test-guest-hardening.sh` (PASS, ~85 s). NOT
verified: the GitHub Actions run itself (needs a push, which needs user
approval), `actionlint` (not installed in WSL), and that the new
`ansible-converge` job works on GitHub's runner (cgroup mount for systemd).

Also done this session: SECURITY.md contact is now
`contact@danielgherasim.com`; `scripts/doctor.sh` now really compares tool
versions with `mise.toml` (it only claimed to) and no longer fails shellcheck.

Decisions still needed from the user: (a) commit + push so CI can be re-run;
(b) approval to apply the SSH drop-in to the VMs; (c) approval for Phase C
step 15 (Cilium) once impact/rollback are stated.

Next action: task 12 (declarative `kubeadm-config.yaml`, validated with
`kubeadm config validate`), then 11, 13, 14. None of these may be applied to
real hosts without approval. Do not change `tofu/` resource attributes
without a real `tofu plan` (needs `PROXMOX_VE_*` env vars) — disk/protection
changes can force VM replacement.

## Verification

- `gh run list` shows `validate` and `security` green on `main`.
- `make validate ALL=1` passes in WSL; `ansible-lint` passes (profile
  `production`) without `|| true`.
- `git grep -nE '192\.168\.'` returns nothing outside `*.example`.
- Docs have a single roadmap; STATUS.md matches `kubectl get nodes` and the
  Proxmox state.
- After Phase C: `kubectl get nodes` all `Ready`, `cilium status` healthy,
  restore test documented.
