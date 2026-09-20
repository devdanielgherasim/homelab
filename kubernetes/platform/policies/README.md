# Network policies

Default-deny per namespace with Cilium's own `CiliumNetworkPolicy`, plus the flows each
namespace needs. Cilium's policies are used, not plain `NetworkPolicy`, for two reasons: they
can name the control-plane node and the other nodes as entities (`kube-apiserver`, `host`,
`remote-node`) without an address, which keeps network topology out of a public repository,
and Hubble reports their verdicts.

| Path | Namespace | Applied by |
|---|---|---|
| `network/monitoring.yaml` | `monitoring` | `../apps/network-policies.yaml` (project `platform`) |
| `network/istio-system.yaml` | `istio-system` | same |
| `network/mesh-demo.yaml` | `mesh-demo` | same |
| `network/demo.yaml` | `demo` | same |
| `argocd/network-policy.yaml` | `argocd` | `../apps/argocd-network-policy.yaml` (project `bootstrap`, the only one allowed to write to `argocd`; prune off) |

Not covered on purpose: `kube-system` (the CNI, DNS, the control plane; a policy there can cut
the cluster off from itself), `cilium-secrets`, `default`. Node-exporter and the Cilium agents
run on the host network and are not endpoints, so pod policies do not apply to them.

## How the policies are built

- `default-deny` selects every pod of the namespace with `ingress: [{}]` and `egress: [{}]`,
  the documented way to enable enforcement with no allowed traffic.
- `allow-dns-and-node-probes`: DNS to CoreDNS, and ingress from the pod's own node (`host`),
  which is where kubelet probes and `kubectl port-forward` come from.
- One policy per workload with exactly the peers and ports seen in Hubble on 2026-09-20 (12,268
  flows from the three agents): who scrapes whom, who reads the API server, who asks istiod.
  The three cases that traffic sampling does not show but that break things are covered
  deliberately: Grafana querying Prometheus, the API server calling istiod's admission webhooks
  (port 15017), and the Argo CD Helm hook Job `argocd-redis-secret-init`, which Argo CD runs
  at every sync.
- The sidecars are selected by the namespace label `istio-injection=enabled`, which Cilium
  copies into the pod identity (`k8s:io.cilium.k8s.namespace.labels.istio-injection`), so a new
  meshed namespace needs no change to istiod's policy.
- Repository access from Argo CD's repo server is `world` on port 443. Narrowing it to names
  needs Cilium's DNS proxy (`toFQDNs`); it is left broad because the chart repositories sit
  behind CDNs whose addresses change.

## Rolling out or changing a policy

Enforcement cuts traffic the moment it is on, and a missing rule is only visible when
something breaks. Cilium's **audit mode** (`policyAuditMode` in
`kubernetes/bootstrap/cilium/values.yaml`) evaluates the policies and reports `AUDIT` verdicts
in Hubble for what they would deny, without denying it. The order:

1. Cilium audit mode on (a platform apply; the agents restart one by one).
2. Push the policies. Argo CD applies them; nothing is denied.
3. Exercise the cluster (a request through the Gateway, a sync of every Application, a change
   to a workload, Grafana and Prometheus in use) and read what Hubble would have denied:

   ```bash
   kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
     hubble observe --verdict AUDIT --since 15m
   ```

4. Fix each entry in the policy files; repeat until there are none.
5. Cilium audit mode off (a platform apply). The policies now deny.
6. Verify again: every Application `Synced/Healthy`, Prometheus targets up, Gateway reachable,
   and that a pod outside the allowed set really is refused.

To add a workload later, start from its `default-deny` namespace: the first `AUDIT`/`DROPPED`
line in Hubble for the new pod tells which rule is missing.
