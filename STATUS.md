# Project Status

Last updated: 2026-09-15 (VM template role + OpenTofu module added).

State legend: **PLANNED** (designed, not built) · **IMPLEMENTED** (code/config
exists, statically validated) · **VALIDATED** (tested against a real or
representative environment) · **DEPLOYED** (running in the actual homelab).

## Current focus

Repository bootstrap: engineering environment, documentation structure, CI,
and AI-agent configuration. **No infrastructure has been provisioned yet.**

## Component status

| Component | State | Notes |
|---|---|---|
| Repository structure / docs / CI | IMPLEMENTED | This bootstrap. |
| Architecture design | PLANNED | `docs/architecture/`, ported from prior design doc. |
| Proxmox host | DEPLOYED | Physically installed (Proxmox VE 9.2), now under Ansible-managed configuration (see below) — VM provisioning still manual/pending. |
| Proxmox bootstrap (network check, API token, SSH key, firewall) | DEPLOYED | `ansible/roles/proxmox_bootstrap/`, all 6 stages run against `pve01` by the user and verified: dedicated OpenTofu API token created, admin SSH key added, firewall rules applied, SSH password auth disabled — confirmed by a direct key-only SSH test after lockdown. One real bug found and fixed mid-rollout: `template` can't write directly to `/etc/pve` (pmxcfs, non-POSIX — worked around with stage-to-`/tmp`-then-`cp`); a fragile `regex_replace`-derived private-key path silently pointed at the `.pub` file instead (replaced with an explicit variable). See `plans/2026-09-15-proxmox-bootstrap-role.md`. |
| Proxmox VM template (Ubuntu 24.04 cloud-init, VMID 9000) | IMPLEMENTED | `ansible/roles/proxmox_template/` — generated, `ansible-lint` (production profile) and `--syntax-check` pass. Not yet run. |
| `vpn01` (Tailscale gateway) | PLANNED | OpenTofu module ready (see below); not applied. |
| `cp01` / `worker01` / `worker02` | PLANNED | OpenTofu module ready (see below); not applied. |
| OpenTofu Proxmox provisioning | IMPLEMENTED | `tofu/modules/proxmox-vm/` + `tofu/environments/homelab/` (provider `bpg/proxmox` v0.113.1) — `tofu fmt -check` and `tofu validate` both pass (verified live in WSL2). **Not applied** — no VM has been created yet. Known caveat: provider has open issues around disk-resize-on-clone, documented in the module's README. |
| Ansible node configuration | PLANNED | `ansible/` has `proxmox_bootstrap` (deployed) and `proxmox_template` (see above); kubeadm/guest-hardening roles not started. |
| Kubernetes bootstrap (kubeadm) | PLANNED | — |
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

Phase 1 — Foundation, remaining:

1. ~~Run `ansible/roles/proxmox_bootstrap/` against the real Proxmox
   host~~ — done 2026-09-15, verified (key-only SSH confirmed working).
2. **Human action**: run `ansible/roles/proxmox_template/`
   (`playbooks/proxmox-template.yml`) to build the Ubuntu 24.04 template —
   not yet run.
3. **Human action**: `cp terraform.tfvars.example terraform.tfvars` in
   `tofu/environments/homelab/`, fill in real values, export
   `PROXMOX_VE_ENDPOINT`/`PROXMOX_VE_API_TOKEN`, then `tofu plan` and
   review before `tofu apply` — see `tofu/README.md`. Depends on step 2.
4. Ansible guest-hardening + containerd/kubeadm-prerequisite roles for
   the VMs once they exist.

Tracked in `plans/`.
