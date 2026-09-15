# Project Status

Last updated: 2026-09-15 (proxmox_bootstrap role deployed and verified).

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
| `vpn01` (Tailscale gateway) | PLANNED | — |
| `cp01` / `worker01` / `worker02` | PLANNED | — |
| OpenTofu Proxmox provisioning | PLANNED | `tofu/` scaffolding only. |
| Ansible node configuration | PLANNED | `ansible/` has the `proxmox_bootstrap` role (see above); kubeadm/guest-hardening roles not started. |
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
2. **OpenTofu module** to provision the Proxmox VMs (`vpn01`, `cp01`,
   `worker01`, `worker02`) from the Ubuntu 24.04 template, using the
   OpenTofu API token created in step 1 (make sure it's stored somewhere
   durable — GitHub Actions Secrets or a local secrets manager — it was
   only ever shown once).
3. Ansible guest-hardening + containerd/kubeadm-prerequisite roles for
   those VMs.

Tracked in `plans/`.
