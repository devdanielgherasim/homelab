# Argo CD (GitOps controller)

Argo CD reconciles this repository into the cluster. It is installed once by hand
(a GitOps controller cannot install itself from nothing), then adopts its own
installation and everything under `kubernetes/platform/apps/`.

- Chart: `argo/argo-cd` **10.9.2** from `https://argoproj.github.io/argo-helm`
  (Argo CD **v3.5.3**).
- Values: [`values.yaml`](values.yaml), used by the bootstrap install and by the
  self-managing Application ([`../../platform/apps/argocd.yaml`](../../platform/apps/argocd.yaml)).
- Design rationale: [ADR-0007](../../../docs/adr/0007-argocd-for-gitops.md) and
  [ADR-0014](../../../docs/adr/0014-gitops-structure.md).

## Version support deviation

Argo CD 3.5 lists Kubernetes **1.33-1.36** as tested; the cluster runs **1.37.0**.
Argo CD uses only stable APIs and the chart's `kubeVersion` allows it, but upstream
has not tested this combination. It is verified here by use (see
[Verification](#verification)) and recorded as a known deviation in `STATUS.md`.

## What is deliberately different from the chart defaults

| Setting | Value | Reason |
|---|---|---|
| `dex`, `notifications`, `redis-ha` | off | No SSO, no notifications, one Redis: less memory. |
| `applicationSet.replicas` | `0` | One app-of-apps root is enough; raise it if a generator is needed. |
| Resource requests | about 350 MiB in total | The cluster has about 5 GB free for the whole platform. |
| `configs.cm.exec.enabled` | `false` | No shell into pods from the UI. |
| `configs.rbac.policy.default` | `""` | Deny by default. |
| NetworkPolicies | on (ingress only) | Cilium enforces them; egress stays open for GitHub and chart repositories. |

Every Argo CD pod runs under the `restricted` Pod Security level (checked with a
server-side dry run of the rendered chart), so the `argocd` namespace enforces
`restricted` without any exemption.

## Projects

[`projects.yaml`](projects.yaml) defines three AppProjects: `bootstrap` (Argo CD
itself and the root app, the only project allowed to write to the `argocd`
namespace), `platform` (shared services, any namespace except `argocd`) and `apps`
(workloads, only the namespaces listed). A project that could target `argocd` would
give its Applications administrator-level access to Argo CD.

## Install

Prerequisites: `kubectl` and `helm` pointed at the cluster, this repository checked
out, and the working tree on the commit that is pushed to `main` (Argo CD reads Git,
not your disk).

```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo

# 1. namespace (with its Pod Security label) and the Argo CD chart
kubectl create -f kubernetes/bootstrap/argocd/namespace.yaml
helm install argocd argo/argo-cd --version 10.9.2 \
  --namespace argocd -f kubernetes/bootstrap/argocd/values.yaml --wait --timeout 10m

# 2. projects, then the root application (which adopts Argo CD and everything else)
kubectl create -f kubernetes/bootstrap/argocd/projects.yaml
kubectl create -f kubernetes/bootstrap/argocd/root.yaml
```

Reach the UI without exposing it:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443   # https://localhost:8080
```

## First login, then rotate

The chart creates an initial admin password in the `argocd-initial-admin-secret`
Secret. Read it once, log in, change it, and delete that Secret (it serves no other
purpose):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
# log in as `admin`, then change the password in the UI (User Info -> Update Password)
kubectl -n argocd delete secret argocd-initial-admin-secret
```

The password hash lives in the `argocd-secret` Secret at runtime. It is not in Git,
and the self-managing Application ignores that Secret's data so a sync never resets
it.

## Verification

```bash
kubectl -n argocd get pods                                # all Running, applicationset at 0
kubectl -n argocd get applications                        # platform, argocd, podinfo: Synced / Healthy
kubectl -n argocd get application argocd -o jsonpath='{.status.sync.status}{"\n"}'
```

Prove the GitOps loop: change `replicaCount` in `kubernetes/apps/podinfo/values.yaml`,
push, and watch the Deployment follow; then scale it by hand and watch self-heal put it
back.

## Rollback

`helm uninstall argocd -n argocd`, then delete the namespace and the three Argo CD
CRDs (`applications`, `applicationsets`, `appprojects`). The workloads Argo CD deployed
keep running: none of its Applications carries a cascade-delete finalizer.
