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

Deployed — installation, values and the verification result are in
[`../../kubernetes/bootstrap/cilium/README.md`](../../kubernetes/bootstrap/cilium/README.md).

- eBPF datapath for pod networking.
- `NetworkPolicy` (default-deny, explicit allow for DNS and required flows
  — see [`../security/`](../security/) once workload policies exist).
- Hubble for flow visibility — the primary tool for the NetworkPolicy and
  CNI failure scenarios in [`infrastructure.md`](infrastructure.md#failure-scenarios-to-practice).

## LoadBalancer addresses (Cilium)

Bare-metal LoadBalancer IP allocation comes from Cilium LB IPAM with L2 announcements,
not MetalLB ([ADR-0015](../adr/0015-loadbalancer-cilium-l2.md)). The pool is a small block
of free addresses on the nodes' LAN, kept in a private inventory; only Services labelled
`homelab.io/lb-pool: private` receive one.

## Istio + Gateway API

North-south traffic enters through an Istio Gateway implementing the
Kubernetes Gateway API, in sidecar mode with `istio-cni`
([ADR-0006](../adr/0006-istio-gateway-api.md), configuration in
[`kubernetes/platform/mesh/`](../../kubernetes/platform/mesh/README.md)). See [`networking.md`](networking.md#kubernetes-traffic-path)
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

The cluster enforces the `baseline` Pod Security level by default (warning and
auditing at `restricted`), with `kube-system` exempt; a namespace that needs more
opts in with a label. Secrets are encrypted at rest and API activity is audited.
The choices, and what was left out on purpose, are in
[ADR-0013](../adr/0013-control-plane-hardening.md); the measured result is in
[`../security/cis-benchmark.md`](../security/cis-benchmark.md).

## Repository layout for this domain

```text
kubernetes/
├── bootstrap/   # cluster bootstrap manifests (CNI, CRDs, core add-ons)
├── platform/    # Argo CD, Kyverno, cert-manager, observability stack
└── apps/        # sample / workload applications, managed via Argo CD
```

The cluster itself is bootstrapped by Ansible (`ansible/roles/kubeadm_*`),
not by manifests. `kubernetes/` stays empty until the first GitOps-managed
component lands — see [`STATUS.md`](../../STATUS.md).
