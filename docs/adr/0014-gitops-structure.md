# 0014. GitOps structure: Argo CD app-of-apps, scoped projects, CNI outside GitOps

Status: Proposed
Date: 2026-09-20

## Context

[ADR-0007](0007-argocd-for-gitops.md) chose Argo CD. Running it on this cluster
raises questions the ADR does not settle: how the applications are organised, how
much each may deploy, how Argo CD is installed and updated, what it must not manage,
and how a public repository stays free of secrets and real addresses. The cluster
has about 5 GB of free RAM in total, so Argo CD's footprint matters too.

## Decision

- **App-of-apps.** A root Application (`kubernetes/bootstrap/argocd/root.yaml`)
  watches the directory `kubernetes/platform/apps/`. Each file there is one
  Application; adding a component means adding a file in Git. Component values live
  next to it (`kubernetes/platform/<component>/`, `kubernetes/apps/<name>/`), and an
  Application installs an upstream Helm chart through **multiple sources**: the chart
  at an exact pinned version, plus the values file from this repository.
- **Argo CD manages itself, carefully.** It is installed once by `helm install` from
  the values file in Git; an Application then adopts that installation from the same
  file. It has no cascade-delete finalizer and `prune: false`, and the chart version
  changes only through a reviewed commit.
- **Three AppProjects.** `bootstrap` (Argo CD and the root; the only project allowed
  to write to the `argocd` namespace), `platform` (shared services, any namespace but
  `argocd`) and `apps` (workloads, listed namespaces only, no cluster-scoped
  resources). A project that could target `argocd` would have administrator-level
  access to Argo CD.
- **Cilium stays outside Argo CD.** The CNI is installed by Helm from
  `kubernetes/bootstrap/cilium/`; a network layer reconciled by a controller that
  runs on top of it can lock itself out, and its values include the API server
  address, which is network topology.
- **Small footprint.** No Dex, no notifications, no HA Redis, and the ApplicationSet
  controller scaled to zero: about 350 MiB of requests.
- **Public repository, no secrets.** Argo CD reads the repository over HTTPS without
  credentials. Anything secret (the Grafana admin password, the Argo CD admin
  password) is created in the cluster by hand and never appears in Git.
- **Manifests are validated in CI** with kubeconform against the Kubernetes 1.37
  schemas plus a pinned commit of the community CRD catalog, so an Application,
  AppProject, Gateway or ServiceMonitor is checked like any core resource.

## Alternatives considered

- **ApplicationSet with a Git directory generator.** Argo CD's documentation prefers
  it to app-of-apps at scale. With a handful of applications and one operator the
  plain root is simpler and lets the ApplicationSet controller stay off; the
  generator is the way to grow if the number of applications does.
- **Flux.** Equivalent capability, no web UI; see ADR-0007.
- **Managing Cilium through Argo CD.** Rejected for the reason above.
- **Argo CD's default projects.** Everything in `default` would let any Application
  deploy anywhere, including into Argo CD's own namespace.

## Consequences

Kubernetes 1.37 is newer than the versions Argo CD 3.5 lists as tested (1.33-1.36).
It uses only stable APIs, and is verified by use; the deviation is recorded in
`STATUS.md`. Every push to `main` is a deployment once an Application points at that
path, so the branch protection and required CI checks are now part of the delivery
path, not just of code review. Applications added to the platform must be reviewed
for their memory budget, because the cluster has little headroom. Status moves from
Proposed to Accepted once the bootstrap has been applied and the loop
(change in Git, sync, self-heal) has been observed.
