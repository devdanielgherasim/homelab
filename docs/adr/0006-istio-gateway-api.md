# 0006. Istio + Kubernetes Gateway API for north-south traffic

Status: Accepted
Date: 2026-09-15

## Context

The lab needs a north-south traffic entry point (routing, TLS termination)
and, per the stated learning goals, exposure to service-mesh concepts
(mTLS, canary/weighted routing, retries, circuit-breaking, authorization
policy) rather than a plain ingress controller alone.

## Decision

Use Istio, configured to implement the Kubernetes Gateway API, as the
north-south traffic layer, with the option to extend individual services
into the mesh for east-west mTLS.

## Alternatives considered

- **A plain Ingress controller (ingress-nginx, Traefik)** — simpler and
  lower resource cost, but provides none of the service-mesh learning
  surface (mTLS, traffic shaping, mesh telemetry) that is an explicit
  project goal.
- **Linkerd** — lighter-weight mesh, but weaker/newer Gateway API story at
  the time of this decision and a smaller feature surface for the traffic
  management patterns (weighted routing, circuit-breaking) the project
  wants to practice.
- **Cilium's own Gateway API/mesh support (Cilium already chosen as CNI)**
  — would reduce the number of moving parts, but the project deliberately
  wants Istio-specific mesh experience as a distinct, portfolio-relevant
  skill from CNI-level networking.

## Consequences

Adds real memory overhead (Istio's control plane and sidecars) on top of
Cilium — must be watched against the 16 GB ceiling; mitigated by keeping
mesh membership opt-in per service rather than cluster-wide by default.
Two networking systems (Cilium + Istio) means two places to look when
debugging traffic — documented explicitly so it isn't a surprise during
troubleshooting.

## Implementation (2026-09-20)

Accepted after the mesh ran on the cluster. Choices made on the way:

- **Sidecar mode with `istio-cni`, not ambient.** Ambient adds a ztunnel pod per node and
  the workers have about 2.5 GB free each. The CNI plugin is chained after Cilium
  (`cni.exclusive: false`), so application pods need no privileged init container, and
  Cilium's socket load balancing is limited to the host namespace so that it does not
  bypass Istio's redirection (`socketLB.hostNamespaceOnly`).
- **Gateway API only.** istiod registers the GatewayClass `istio` and creates the gateway
  Deployment and LoadBalancer Service from a `Gateway`; there is no `VirtualService`.
  The Service gets its address from Cilium (ADR-0015) through the label
  `homelab.io/lb-pool: private`.
- **Opt-in injection.** Only namespaces labelled `istio-injection=enabled` are meshed
  (today `mesh-demo`); `istio-system` is the only privileged namespace, for the CNI agent.
- **Installed by Argo CD** in sync waves: Gateway API CRDs (-2), `istio-base` (-1),
  `istio-cni` (0), `istiod` (1), `mesh-demo` (2).

Verified on the cluster: sidecars injected on both workers under Pod Security `baseline`;
200 requests through the Gateway split 187/13 between the two podinfo versions (weights
90/10); with `PeerAuthentication` STRICT, plain traffic from a namespace without a
sidecar is reset while traffic between meshed pods is reported as `mutual_tls`.

Istio 1.31 lists Kubernetes 1.32-1.36 as supported and the cluster runs 1.37, the same
kind of deviation as for Cilium and Argo CD (see `STATUS.md`).
