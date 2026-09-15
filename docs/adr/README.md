# Architecture Decision Records

ADRs capture meaningful architectural decisions — not every implementation
detail. Use `.claude/skills/create-adr/SKILL.md` (or `/adr`) to create one.

## Status values

- **Proposed** — drafted, not yet confirmed by the project owner.
- **Accepted** — confirmed and in effect.
- **Superseded** — replaced by a later ADR (link both ways).
- **Rejected** — considered and declined; kept for the record.

## Index

| # | Title | Status |
|---|---|---|
| [0001](0001-proxmox-as-hypervisor.md) | Proxmox VE as hypervisor | Proposed |
| [0002](0002-ubuntu-server-guest-os.md) | Ubuntu Server 24.04 LTS as guest OS | Proposed |
| [0003](0003-upstream-kubernetes-over-k3s.md) | Upstream Kubernetes (kubeadm) over k3s/managed distros | Proposed |
| [0004](0004-opentofu-over-terraform.md) | OpenTofu instead of Terraform | Proposed |
| [0005](0005-cilium-as-cni.md) | Cilium as CNI | Proposed |
| [0006](0006-istio-gateway-api.md) | Istio + Kubernetes Gateway API for north-south traffic | Proposed |
| [0007](0007-argocd-for-gitops.md) | Argo CD for GitOps | Proposed |
| [0008](0008-vpn-only-management-plane.md) | VPN-only management plane (Tailscale) | Proposed |

New ADRs get the next sequential number and are added to this table.
