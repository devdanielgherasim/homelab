# Security Architecture

General security posture for the homelab itself (as opposed to
[`public-repository.md`](public-repository.md), which covers the risks of
publishing this repo). Status: design reference — see
[`STATUS.md`](../../STATUS.md).

| Control | Required posture |
|---|---|
| Internet exposure | No direct exposure of management interfaces |
| Host access | SSH keys only; no password login; no direct root SSH |
| MFA | Enabled wherever supported for VPN/Git/administrative identity |
| Firewall | Default deny; permit explicit management and application flows only |
| Kubernetes network | Default-deny `NetworkPolicy`; explicitly allow DNS and required service flows |
| Workload security | `runAsNonRoot`, no privilege escalation, dropped Linux capabilities, read-only root filesystem where possible |
| Admission control | Kyverno policies prevent privileged pods, unsafe host access, non-compliant images |
| Vulnerability management | Trivy scanning in CI; fail builds on selected high/critical findings after policy tuning |
| Secrets | SOPS + age (pending threat-model ADR — see [`public-repository.md`](public-repository.md#secret-handling)); encrypted at rest in Git once adopted; minimize Secret RBAC access |
| Images | Immutable tags/digests preferred; avoid `:latest` for controlled environments |
| Proxmox | Private management network, firewall enabled, strong authentication, regular updates |

This table is the target posture, not a claim of current implementation —
cross-check [`STATUS.md`](../../STATUS.md) before asserting any row is live.
