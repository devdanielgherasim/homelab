# 0005. Cilium as CNI

Status: Accepted
Date: 2026-09-15

## Context

The cluster needs a CNI providing pod networking, `NetworkPolicy`
enforcement, and ideally deep network observability — the latter directly
supports the project's networking/troubleshooting learning goals and the
"NetworkPolicy denial" and "CNI failure" practice scenarios in
[`../architecture/infrastructure.md`](../architecture/infrastructure.md#failure-scenarios-to-practice).

## Decision

Use Cilium as the cluster CNI, with Hubble enabled for flow visibility.

## Alternatives considered

- **Calico** — solid, widely used `NetworkPolicy` implementation, but lacks
  Cilium's eBPF-based Hubble flow visibility, which is directly useful for
  the troubleshooting scenarios this project targets.
- **Flannel** — simple overlay networking, no native `NetworkPolicy`
  enforcement — would require bolting on a separate policy engine,
  defeating the point of a single coherent CNI choice.
- **kube-router** — smaller ecosystem and community than Cilium; less
  aligned with current production adoption trends worth demonstrating.

## Consequences

eBPF requires a reasonably current kernel (satisfied by Ubuntu 24.04 —
[ADR 0002](0002-ubuntu-server-guest-os.md)). Cilium is heavier than Flannel
at rest; acceptable under the sizing in
[`../architecture/infrastructure.md`](../architecture/infrastructure.md).
Hubble becomes the default tool for network troubleshooting runbooks.

Deployed on 2026-09-19 as Cilium 1.20.2 with kube-proxy replacement, Hubble
relay and UI, and Envoy disabled (no L7 features; Gateway API is provided by
Istio, [ADR 0006](0006-istio-gateway-api.md)). Cilium 1.20.2's compatibility
table lists Kubernetes 1.33-1.36 as tested; this cluster runs 1.37.0, so the
combination is outside upstream's tested matrix. It was verified with the
official connectivity test instead; see
[`../../kubernetes/bootstrap/cilium/README.md`](../../kubernetes/bootstrap/cilium/README.md).
