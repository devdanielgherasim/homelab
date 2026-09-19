# Service mesh and Gateway API

Istio in sidecar mode (with the istio-cni plugin) plus the Kubernetes Gateway API,
and a small demo that splits traffic 90/10 between two versions of one app.
Everything is installed by Argo CD from `kubernetes/platform/apps/`; the Helm
values for the three Istio charts are in this directory.

## What each piece is

| Piece | Where | What it does |
|---|---|---|
| Gateway API CRDs | `apps/gateway-api.yaml` | `Gateway`, `HTTPRoute`, `GatewayClass` and friends, standard channel v1.6.2, straight from the upstream repository (`config/crd` at tag `v1.6.2`). |
| `istio/base` 1.31.0 | `apps/istio-base.yaml`, `values-istio-base.yaml` | Istio's own CRDs, cluster roles and the validating webhook. Also owns the `istio-system` namespace. |
| `istio/cni` 1.31.0 | `apps/istio-cni.yaml`, `values-istio-cni.yaml` | DaemonSet that chains the `istio-cni` plugin after Cilium. It sets up the traffic redirection into the sidecar, so application pods do not need the privileged `istio-init` container. |
| `istio/istiod` 1.31.0 | `apps/istiod.yaml`, `values-istiod.yaml` | The control plane: sidecar injection, certificates for mTLS, xDS to the proxies, and the Gateway API controller. |
| Demo | `apps/mesh-demo.yaml`, `kubernetes/apps/mesh-demo/` | Two podinfo versions, a `Gateway`, an `HTTPRoute` with weights 90/10, and a strict-mTLS `PeerAuthentication`. |

The gateway is not the `istio/gateway` chart. Istio creates it from a Gateway API
`Gateway` of class `istio` (istiod registers that GatewayClass itself), as a
Deployment and a LoadBalancer Service named `<gateway>-istio` in the Gateway's
namespace. There is no VirtualService anywhere: routing is Gateway API only.

### Sync order

Waves on the Argo CD Applications (lower first, each must be healthy before the
next starts): `gateway-api` -2, `istio-base` -1, `istio-cni` 0, `istiod` 1,
`mesh-demo` 2. The CNI agent goes before istiod so no pod is injected for CNI mode
while the plugin is missing.

## Versions and why

- **Gateway API v1.6.2, standard channel.** Standard is the stable subset; the
  experimental channel would only add alpha kinds nothing here uses. The release's
  `standard-install.yaml` was downloaded and its sha256 checked
  (`faede450...ca40d9`, matching the published digest and the value in the research
  notes), and the resource list of `config/crd` at the tag is identical to it (10
  CRDs, the `safe-upgrades` ValidatingAdmissionPolicy and its binding).
  **Installed from upstream, not vendored:** `config/crd` exists at the tag and is a
  plain kustomize base, so Argo CD renders it directly and a bump is a one-line
  change to `targetRevision`. Vendoring would put 1.1 MB of generated YAML in
  the repository. The trade-off is that Argo CD trusts a Git tag in someone else's
  repository (tags can be moved); the sha256 above is what to compare against
  after a bump. The CRDs need `ServerSideApply=true`, which is set.
- **Istio 1.31.0.** Latest release when this was written. Images come from
  `docker.io/istio`, which is the chart default for `global.hub` (checked in
  `helm show values`), so no override is set and the tag follows the chart version.
- **Sidecar mode with istio-cni, no ambient/ztunnel.** Ambient needs more per-node
  memory and this cluster has about 2.5 GB free per worker.

## Kubernetes 1.37 is not on Istio's support list

Istio 1.31 lists Kubernetes 1.32 to 1.36 as supported
(<https://istio.io/latest/docs/releases/supported-releases/>, checked when this was
written); 1.37 is not mentioned. This cluster runs 1.37.0. It should work, since
Istio only uses stable APIs, but it is untested by the project: report problems as
"unsupported platform", and expect to wait for an Istio release that lists 1.37
before treating a mesh bug as an Istio bug.

## Settings the other components must have

### Cilium (the lead applies these in Cilium's own values)

```yaml
cni:
  exclusive: false        # currently true on the cluster
socketLB:
  hostNamespaceOnly: true # key exists in chart 1.20.2, commented out (default false)
```

- `cni.exclusive: false`: Cilium otherwise renames every other CNI config in
  `/etc/cni/net.d` to `*.cilium_bak`, which would remove the istio-cni entry.
- `socketLB.hostNamespaceOnly: true`: Istio's redirection rules must see traffic to
  Services; Cilium's socket load balancer would translate the address inside the
  pod first and bypass them. At the time of writing the live ConfigMap has
  `bpf-lb-sock: "false"` (socket LB off), so this is not biting yet, but set it so
  that turning socket LB on later does not silently break the mesh.
- The Gateway's generated Service carries the label `homelab.io/lb-pool: private`
  (from `spec.infrastructure.labels` in `gateway.yaml`). Cilium's LB IPAM pool and
  L2 announcement policy must select Services by that label. No address is stored
  in Git.

### Pod Security

| Namespace | Label | Why |
|---|---|---|
| `istio-system` | `enforce: privileged` (set by `apps/istio-base.yaml` through `managedNamespaceMetadata`) | `istio-cni-node` mounts hostPath volumes (CNI bin/conf dirs, procfs, netns) and adds `SYS_ADMIN`, `NET_ADMIN`, `NET_RAW`, `SYS_PTRACE`, `DAC_OVERRIDE`, runs as root with an unconfined AppArmor profile. |
| `mesh-demo` | `istio-injection: enabled`, `enforce: baseline`, `warn/audit: restricted` (`apps/mesh-demo.yaml`) | With istio-cni the injected sidecar has no `NET_ADMIN`, so baseline is enough. |

What the dry runs showed (cluster default is enforce baseline, warn/audit
restricted; `--dry-run=server` into `default`, since the labelled namespaces do not
exist yet):

- The rendered `istio-cni-node` DaemonSet gives a `restricted:latest` warning
  listing exactly the items above (hostPath volumes, added capabilities, root,
  unconfined AppArmor). A bare Pod with a hostPath volume and `SYS_ADMIN` is
  rejected in `default` with `violates PodSecurity "baseline:latest"` and accepted
  in `kube-system` (exempt). So `istio-system` does need the `privileged` label, and
  without it the DaemonSet would be created but its pods rejected.
- The istiod Deployment renders with no Pod Security warnings.
- Both podinfo Deployments produce no warnings at all (no baseline, no restricted).
- **Not verified:** the injected pod (app container plus `istio-proxy` and the
  `istio-validation` init container). Injection happens when the Pod is created,
  which a dry run of the Deployment does not do, so the baseline claim for injected
  sidecars rests on Istio's documented CNI behaviour. The values set
  `seccompProfile: RuntimeDefault` on istiod, istio-cni and the proxies to reduce
  restricted warnings; check the events of the first demo pods for a
  `would violate PodSecurity` line.

## RAM budget (requests)

| Component | Count | Request each | Total |
|---|---|---|---|
| istiod | 1 | 256Mi | 256Mi |
| istio-cni-node (one per node, control plane included) | 3 | 50Mi | 150Mi |
| Gateway Envoy (generated, uses the proxy defaults) | 1 | 64Mi | 64Mi |
| Sidecars on the two podinfo pods | 2 | 64Mi | 128Mi |
| podinfo containers | 2 | 16Mi | 32Mi |
| **Total** | | | **630Mi** |

The platform part (istiod plus istio-cni) is 406Mi; the demo adds 224Mi. CPU
requests total about 50m + 30m + 10m + 20m + 20m = 130m. Limits are memory only
(istiod 512Mi, istio-cni 128Mi each, proxies 256Mi, podinfo 64Mi); the chart defaults
would have been 2048Mi for istiod and 128Mi per sidecar. The two workers have about
2.5 GB free each, and istiod (no anti-affinity, no node selector) will land on
one of them.

## Verify after sync

`istioctl` is not installed, so kubectl only.

```sh
# Applications healthy and synced
kubectl -n argocd get applications gateway-api istio-base istio-cni istiod mesh-demo

# CRDs and the GatewayClass that istiod registers
kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
kubectl get gatewayclass istio          # ACCEPTED should be True

# Control plane and CNI agents (3 istio-cni-node pods, all Ready)
kubectl -n istio-system get pods -o wide
kubectl -n istio-system logs ds/istio-cni-node --tail=20

# Chained plugin present on a node, and Cilium's config not renamed
# (needs node access): ls /etc/cni/net.d   -> 05-cilium.conflist, no *.cilium_bak

# Demo pods have two containers (app + istio-proxy) and an istio-validation init container
kubectl -n mesh-demo get pods
kubectl -n mesh-demo get pod -l app=podinfo -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{" | "}{.spec.initContainers[*].name}{"\n"}{end}'

# Gateway and route accepted, and the Service got an address from Cilium
kubectl -n mesh-demo get gateway demo       # PROGRAMMED True, ADDRESS filled in
kubectl -n mesh-demo describe httproute podinfo | grep -A3 -i "accepted\|resolvedrefs"
kubectl -n mesh-demo get svc demo-istio --show-labels   # label homelab.io/lb-pool=private

# Weighted split: ~90% v1 (6.14.1), ~10% v2 (6.15.0). Use the Gateway address, or
# kubectl -n mesh-demo port-forward svc/demo-istio 8080:80 and 127.0.0.1:8080.
for i in $(seq 1 100); do curl -s http://<gateway-address>/ | grep -o '"version": *"[0-9.]*"'; done | sort | uniq -c

# Strict mTLS: a plaintext request from a pod outside the mesh to a podinfo pod must fail
kubectl run probe --rm -it --image=curlimages/curl --restart=Never -n default -- \
  curl -sS -m 5 http://podinfo-v1.mesh-demo.svc:9898/     # expect: connection reset / empty reply
# ...while the public gateway listener keeps accepting plaintext HTTP (previous step).
```

The last point (gateway accepts plaintext while the namespace is STRICT) is expected
from how Istio applies PeerAuthentication to sidecar inbound listeners, but has not
been run: no cluster had the mesh installed when this was written.

## Rollback

Argo CD Applications here have no `resources-finalizer`, so deleting an Application
file from `kubernetes/platform/apps/` removes the Application object but leaves
what it deployed. To take a piece out:

1. Remove the demo first: delete `mesh-demo`'s Gateway/HTTPRoute (or the
   Application with `argocd app delete mesh-demo --cascade`), then remove the
   `istio-injection` label and restart the workloads in any injected namespace
   (`kubectl rollout restart`) so they lose their sidecars.
2. Then, in this order, `istiod`, `istio-cni`, `istio-base`, `gateway-api`: revert
   the Git commit (or delete the Application with cascade). Deleting `istio-base`
   deletes Istio's CRDs and every Istio resource in the cluster; deleting
   `gateway-api` deletes every Gateway and HTTPRoute.
3. To roll back only a version bump, revert the `targetRevision` change and read
   the Istio release notes for downgrade constraints first.
4. Cilium: if istio-cni is removed for good, `cni.exclusive` can go back to `true`.
5. `istio-cni-node` removes its own entry from the CNI chain on shutdown; if a node
   was left with a stale `istio-cni` in `/etc/cni/net.d/05-cilium.conflist`, new
   pods on it fail with a missing-plugin error until the entry is removed.

## Not done here

- cert-manager and Istio's `istio-csr` are deferred: istiod uses its built-in CA.
- TLS on the demo listener (HTTP only, reached over the LAN/Tailscale).
- Kubernetes NetworkPolicy for the mesh namespaces.
