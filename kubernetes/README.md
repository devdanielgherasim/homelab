# kubernetes/

Kubernetes manifests, owned by Argo CD once the cluster exists. See
[`../docs/architecture/kubernetes.md`](../docs/architecture/kubernetes.md)
and [`../docs/architecture/gitops.md`](../docs/architecture/gitops.md).

## Layout (created as content lands, not pre-scaffolded)

```text
kubernetes/
├── bootstrap/   # one-time: installs Argo CD itself (not GitOps-managed, by definition)
├── platform/    # Cilium, MetalLB, Istio/Gateway API, cert-manager, Kyverno, observability
└── apps/        # sample / workload applications
```

## Rules

- `kubectl apply`/`delete` against a real cluster is never run by an agent
  or a hook without explicit human approval — see
  [`../AGENTS.md`](../AGENTS.md#destructive-action-policy). Desired state
  changes go through Git + Argo CD reconciliation, not direct `kubectl`.
- `yamllint` and `kubeconform -strict` must pass before commit; `helm
  lint` for any chart-based content — enforced in CI.
- No kubeconfig, service-account token, or cluster-specific secret is ever
  committed — see
  [`../docs/security/public-repository.md`](../docs/security/public-repository.md).

## Status

No manifests exist yet — see [`../STATUS.md`](../STATUS.md).
