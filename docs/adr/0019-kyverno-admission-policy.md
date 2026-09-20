# 0019. Kyverno for admission policy: the new CEL policy type, audit first, failing open

Status: Proposed
Date: 2026-09-20

## Context

Pod Security admission already enforces `baseline` cluster-wide and `restricted` in the
namespaces that opt in, and network policy is default-deny (ADR-0017). What neither does is the
workload hygiene that is not about privilege: images pinned to a tag, resource requests and
limits, images from the registries this lab trusts, no NodePort Services, and no namespace
quietly labelled `privileged` (the label is the escape hatch from Pod Security admission). Kyverno is
the admission controller that covers this, and it is the piece a reviewer expects in a
production-grade cluster.

It is also a piece that can hurt: its webhooks sit in the path of every create, the API server
already holds 1.2 GiB with 48 CRDs, and the workers have little memory to spare.

## Decision

Install Kyverno (chart 3.9.1, Kyverno v1.19.1) through Argo CD, trimmed:

- **Policies are written in the new type only.** The chart marks the legacy `ClusterPolicy` and
  `Policy` types deprecated in favour of `policies.kyverno.io`, so the rules here are
  `ValidatingPolicy` (CEL). The CRDs could not be trimmed the way this decision first assumed:
  Kyverno 1.19.1 **will not start without the legacy `ClusterPolicy` and `Policy` CRDs** (the
  admission controller exits at its sanity check and the reports controller cannot list them),
  even though nothing here uses them, and the chart ignores the switches of the
  `policies.kyverno.io` group. That leaves 20 CRDs and about 5.8 MiB of schema, against 22 and
  5.6 MiB by default: only the two cleanup CRDs (with the cleanup controller) are saved.
- **Validation only.** The background and cleanup controllers, which serve mutate-existing,
  generate and scheduled deletion, are off. What runs is the admission controller (one replica)
  and the reports controller, about 190 MiB of requests in all.
- **Audit first, then enforce.** Every policy starts with `validationActions: [Audit]`: nothing
  is refused, and policy reports list what would be. A policy moves to `Deny` only after its
  report is clean or its findings are fixed or excepted, the same route as the network policies.
- **Fail open.** Policy webhooks use `failurePolicy: Ignore`. With one control plane and one
  admission replica, a Kyverno outage must not stop the cluster from creating anything, and the
  cost is that an outage also stops policy from being applied. This is written down as a
  trade-off, not hidden.
- **Namespace** `kyverno`, `restricted` Pod Security, like the other platform components; a
  default-deny network policy for it comes after the install has been observed.

## Alternatives considered

- **Legacy `ClusterPolicy` (YAML patterns, JMESPath).** More examples exist, but the type is
  deprecated, its CRD is 1.4 MiB, and rules written in it would have to be migrated.
- **`ValidatingAdmissionPolicy` from Kubernetes itself.** No component to run and CEL as well,
  but no policy reports, no exceptions and no path to image verification or mutation later.
  Kyverno's new policy type is also CEL, so the rules written here stay close to what this
  alternative would need if Kyverno were ever dropped.
- **OPA Gatekeeper.** Rego, a second language for the same job, and heavier.
- **Fail closed.** The right setting for a hardened multi-replica cluster; here it would let a
  single crashed pod block every workload, on a control plane that cannot be replaced quickly.

## Consequences

One more component in the request path, and about 5.8 MiB of CRD schema for the API server to
hold, on top of 48 CRDs and about 1.2 GiB. The install is measured on the running cluster (API
server memory, node memory, webhook latency) and the numbers are recorded here.

What the first rollout found (2026-09-20), because the design above had been written from the
chart's values and templates and not from a run: the admission controller crash-looped on the
missing legacy CRDs (nothing was cut: it never registered a webhook), and 11 of the
`policies.kyverno.io` CRDs showed as `OutOfSync` forever, the whole difference being two empty
maps (`labels: {}` and `annotations: {}`) that the chart renders and the live objects do not have;
the Application now ignores those two fields on CRDs. The Argo CD managed-resources API was what
showed the real diff, after `kubectl diff --server-side` had shown none.

Policies live in `kubernetes/platform/policies/kyverno/`. Uninstalling needs the webhook
configurations removed (the chart's pre-delete hook does it; whether Argo CD 3.5 runs
that hook has to be checked, and until then it is a manual step). Kyverno 1.19 is not documented
as tested on Kubernetes 1.37, like the other components (see `STATUS.md`).

## Measured cost of the install (2026-09-20)

Taken on the running cluster before Kyverno and once it was `Synced/Healthy` with no policy yet:

| | Before | After |
|---|---|---|
| `kube-apiserver` memory | 1,148 MiB | **1,612 MiB (+464 MiB, +40%)** |
| API server heap in use | 774 MiB | 1,129 MiB |
| `cp01` memory | 65% (2,487 MiB) | **74% (2,843 MiB)** of 3,915 MiB |
| CRDs | 48 | 68 |
| Kyverno pods | none | admission 62 MiB, reports 33 MiB |
| Applications, Prometheus targets | 16, 27 up | 17 `Synced/Healthy`, 27 up |

The pods are cheap; the cost is on the control plane. Most likely it is the CRD schemas (5.8 MiB,
above all the two legacy types the controllers insist on) plus the watches of the controllers;
the two were not measured separately, so this is an inference, not a finding. The resource
webhooks are empty until a policy
exists (Kyverno registers them on demand), so requests are not affected yet; the webhooks that are
registered (`failurePolicy: Fail`) cover only Kyverno's own policy and exception objects, not
workloads. Latency per request was not measurable without a policy and will be measured once
policies exist.

The consequence that matters for planning: the control plane, already raised to 4 GiB, is at 74%
and the host has about 2 GiB free, so **anything else that brings many CRDs (the Trivy operator
would) has to be weighed against this number first**. Two ways to make room without adding memory
to the host: take 512 MiB from a worker (about 55-60% used) and give it to `cp01`, or replace
Kyverno by Kubernetes' own `ValidatingAdmissionPolicy`, which needs no CRDs of its own and covers
the first five rules here (no policy reports or exceptions, though).
