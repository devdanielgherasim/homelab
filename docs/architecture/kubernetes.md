# Kubernetes

Status: design reference — see [`STATUS.md`](../../STATUS.md).

## Cluster

Upstream Kubernetes bootstrapped with `kubeadm` on containerd, deliberately
chosen over a simplified local-dev distribution (k3s, kind, minikube) —
see [`../adr/0003-upstream-kubernetes-over-k3s.md`](../adr/0003-upstream-kubernetes-over-k3s.md)
for the rationale. One control-plane node (`cp01`) plus two workers
(`worker01`, `worker02`) — see [`infrastructure.md`](infrastructure.md) for
sizing.

## Cilium (CNI)

- eBPF datapath for pod networking.
- `NetworkPolicy` (default-deny, explicit allow for DNS and required flows
  — see [`../security/`](../security/) once workload policies exist).
- Hubble for flow visibility — the primary tool for the NetworkPolicy and
  CNI failure scenarios in [`infrastructure.md`](infrastructure.md#failure-scenarios-to-practice).

## MetalLB

Bare-metal LoadBalancer IP allocation from the LoadBalancer pool defined in
[`networking.md`](networking.md#addressing-plan) (`10.10.30.0/24`).

## Istio + Gateway API

North-south traffic enters through an Istio Gateway implementing the
Kubernetes Gateway API. See [`networking.md`](networking.md#kubernetes-traffic-path)
for the routing diagram. East-west traffic can optionally join the mesh
for mTLS between services. Features to exercise: mTLS, weighted
routing/canary deployment, timeouts, retries, circuit-breaking, telemetry,
authorization policies.

## cert-manager

Certificate automation for internal application endpoints — issued
certificates stay internal; this is not a publicly trusted CA setup.

## Policy and scanning

- **Kyverno** — admission policies: no privileged pods, no unsafe host
  access, compliant images only.
- **Trivy** — container and IaC vulnerability scanning (also runs in CI on
  IaC source, see [`../../.github/workflows/security.yml`](../../.github/workflows/security.yml)).

## Workload security baseline

`runAsNonRoot`, no privilege escalation, dropped Linux capabilities,
read-only root filesystem where possible. Immutable tags/digests preferred
over `:latest`.

## Repository layout for this domain

```
kubernetes/
├── bootstrap/   # cluster bootstrap manifests (CNI, CRDs, core add-ons)
├── platform/    # Argo CD, Kyverno, cert-manager, observability stack
└── apps/        # sample / workload applications, managed via Argo CD
```

Currently holds only a `README.md` — see [`STATUS.md`](../../STATUS.md).
