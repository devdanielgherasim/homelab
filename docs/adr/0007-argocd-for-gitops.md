# 0007. Argo CD for GitOps

Status: Proposed
Date: 2026-09-15

## Context

The project's GitOps principle requires Git to be the source of truth for
platform and application desired state, reconciled continuously rather
than applied ad hoc via `kubectl`. A GitOps controller is needed once the
cluster is bootstrapped.

## Decision

Use Argo CD to continuously reconcile platform and application manifests
under `kubernetes/platform/` and `kubernetes/apps/` from this Git
repository.

## Alternatives considered

- **Flux** — comparable capability and a valid alternative; Argo CD's web
  UI gives more immediate visual feedback for a learning-focused single-
  operator lab, and it's the more commonly requested GitOps tool in
  Platform Engineering job postings this project is meant to demonstrate
  fluency for.
- **Manual `kubectl apply` from CI** — directly violates the stated GitOps
  and "Git as source of truth" principles; no drift detection or
  continuous reconciliation.

## Consequences

Argo CD itself must be bootstrapped once via a non-GitOps step (Ansible or
a one-time manifest apply) before it can manage itself and everything
else — this bootstrap boundary is documented in
[`../architecture/gitops.md`](../architecture/gitops.md#infrastructure-vs-platform-boundary).
Cluster state should always be explainable by "what's in Git," which also
shapes the destructive-action policy in [`../../AGENTS.md`](../../AGENTS.md).
