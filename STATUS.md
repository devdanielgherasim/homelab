# Project Status

Last updated: 2026-09-15.

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
| Proxmox host | PLANNED | Physically installed (Proxmox VE 9.2) but not yet under IaC management. |
| `vpn01` (Tailscale gateway) | PLANNED | — |
| `cp01` / `worker01` / `worker02` | PLANNED | — |
| OpenTofu Proxmox provisioning | PLANNED | `tofu/` scaffolding only. |
| Ansible node configuration | PLANNED | `ansible/` scaffolding only. |
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

Phase 1 — Foundation: OpenTofu module to provision the Proxmox VMs
(`vpn01`, `cp01`, `worker01`, `worker02`) from the Ubuntu 24.04 template,
plus the Ansible base-hardening role. Tracked in `plans/`.
