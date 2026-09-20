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
| [0001](0001-proxmox-as-hypervisor.md) | Proxmox VE as hypervisor | Accepted |
| [0002](0002-ubuntu-server-guest-os.md) | Ubuntu Server 24.04 LTS as guest OS | Accepted |
| [0003](0003-upstream-kubernetes-over-k3s.md) | Upstream Kubernetes (kubeadm) over k3s/managed distros | Accepted |
| [0004](0004-opentofu-over-terraform.md) | OpenTofu instead of Terraform | Accepted |
| [0005](0005-cilium-as-cni.md) | Cilium as CNI | Accepted |
| [0006](0006-istio-gateway-api.md) | Istio + Kubernetes Gateway API for north-south traffic | Accepted |
| [0007](0007-argocd-for-gitops.md) | Argo CD for GitOps | Accepted |
| [0008](0008-vpn-only-management-plane.md) | VPN-only management plane (Tailscale) | Proposed |
| [0009](0009-flat-network-until-vpn.md) | Single flat network until the VPN and segmentation exist | Accepted |
| [0010](0010-local-opentofu-state.md) | Local OpenTofu state for a single operator | Accepted |
| [0011](0011-proxmox-api-token-privileges.md) | Privilege-separated Proxmox API token, scoped to a pool | Accepted |
| [0012](0012-local-backups.md) | Backups stay on the Proxmox host, and cover only what has state | Accepted |
| [0013](0013-control-plane-hardening.md) | Control-plane hardening, and what is deliberately left out | Accepted |
| [0014](0014-gitops-structure.md) | GitOps structure: Argo CD app-of-apps, scoped projects, CNI outside GitOps | Accepted |
| [0015](0015-loadbalancer-cilium-l2.md) | LoadBalancer addresses from Cilium (LB IPAM + L2 announcements), not MetalLB | Accepted |
| [0016](0016-platform-bootstrap-with-opentofu.md) | Platform bootstrap (Cilium, Argo CD, secrets) with OpenTofu, not by hand | Accepted |
| [0017](0017-network-policies-default-deny.md) | Default-deny network policies with Cilium, rolled out through audit mode | Accepted |
| [0018](0018-kubelet-serving-certificates.md) | Kubelet serving certificates from the cluster CA, and metrics-server that verifies them | Accepted |
| [0019](0019-kyverno-admission-policy.md) | Kyverno for admission policy: the new CEL policy type, audit first, failing open | Proposed |

New ADRs get the next sequential number and are added to this table.

ADRs 0001-0007 and 0014-0018 are implemented and in use. 0008 (platform layer not built
yet) stays **Proposed** until the corresponding
component is deployed and the decision is confirmed.
