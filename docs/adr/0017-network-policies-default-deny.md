# 0017. Default-deny network policies with Cilium, rolled out through audit mode

Status: Accepted
Date: 2026-09-20

## Context

Until now every pod could talk to every other pod and to the internet: the only policies were
the four ingress-only `NetworkPolicy` objects of the Argo CD chart. A default-deny per
namespace is the baseline of a production cluster, and the risk is in the rollout: a rule that
was missed cuts a service, and the policies here have to hold for Argo CD, Prometheus, the
Istio control plane and the demo, which depend on each other in ways that are easy to forget
(the API server calling admission webhooks, an Argo CD hook Job, Grafana querying Prometheus).

## Decision

Use Cilium's own `CiliumNetworkPolicy`, one `default-deny` per namespace plus one policy per
workload, in `kubernetes/platform/policies/`. Write them from the traffic Hubble actually
shows, and introduce them through Cilium's **audit mode** (`policyAuditMode`): policies are
evaluated and Hubble reports what they would deny, but nothing is denied. Enforcement is
switched on (`policyAuditMode: false`) only after the audit is clean and has been checked with
a negative control. `kube-system`, `cilium-secrets` and `default` are not covered.

Addresses stay out of the public repository: the control-plane node and the other nodes are
the entities `kube-apiserver`, `host` and `remote-node`, the internet is `world`, and the
sidecars are selected by the namespace label `istio-injection=enabled`.

## Alternatives considered

- **Plain Kubernetes `NetworkPolicy`.** Portable, but it cannot name the API server or the
  nodes without an `ipBlock` with a real address, which is network topology in a public
  repository, and its verdicts are not visible in Hubble.
- **Enforce straight away and fix what breaks.** Simpler, and exactly how a missing rule
  becomes an outage. The audit costs two Cilium restarts and finds the gaps first.
- **Cilium's host firewall or policies for `kube-system`.** They can lock the cluster out of
  itself; left for later, if ever.
- **Narrowing Argo CD's repository access to names (`toFQDNs`).** Needs Cilium's DNS proxy and
  the chart repositories sit behind CDNs; the repo server keeps HTTPS to `world`.

## Consequences

Traffic that is not listed is refused, which is the point, and each new workload needs a policy
(`kubernetes/platform/policies/README.md` says how: start from the first denied flow in
Hubble). The API server's Service proxy is allowed to Prometheus and Grafana, because Lens and
`kubectl get --raw` use it. `podinfo` probing the cloud metadata address is refused on purpose.

Result of the rollout (2026-09-20): the audit found four paths, all explained (Grafana's plugin
update check to the internet, now switched off; the API server's proxy, now allowed; podinfo's
metadata probe, kept denied). A negative control proved that the audit reports what
enforcement would deny. After enforcement, all 12 Applications stayed `Synced/Healthy`, all 27
Prometheus targets `up`, the Gateway answered 40 of 40, an Argo CD sync (with its hook Job) and a
new meshed pod succeeded, and a test pod was refused for the internet and for another
namespace while its DNS still worked.

Not covered: Kyverno-style admission policy (next in G5), egress by name, `kube-system`.
Two residual drops are not from these policies' workloads and touch nothing: ICMPv6 between
unresolved identities.
