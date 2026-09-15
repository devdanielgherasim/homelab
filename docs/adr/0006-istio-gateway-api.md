# 0006. Istio + Kubernetes Gateway API for north-south traffic

Status: Proposed
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
