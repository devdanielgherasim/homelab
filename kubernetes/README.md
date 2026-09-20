# kubernetes/

Kubernetes manifests, owned by Argo CD once the cluster exists. See
[`../docs/architecture/kubernetes.md`](../docs/architecture/kubernetes.md)
and [`../docs/architecture/gitops.md`](../docs/architecture/gitops.md).

## Layout (created as content lands, not pre-scaffolded)

```text
kubernetes/
├── bootstrap/   # applied by tofu/environments/platform: Cilium, and Argo CD itself (values, namespace, projects, root app)
├── platform/
│   └── apps/    # one Argo CD Application per file, watched by the root app-of-apps
└── apps/        # values and manifests of the workloads
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
