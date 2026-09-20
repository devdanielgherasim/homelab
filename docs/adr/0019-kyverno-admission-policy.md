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

- **The new policy type only.** The chart marks the legacy `ClusterPolicy` and `Policy` types
  deprecated in favour of `policies.kyverno.io`. Policies are written as `ValidatingPolicy`
  (CEL, evaluated by the API machinery's expression engine, no JSON-patch engine). The two legacy
  CRDs, 1.4 MiB of schema each, are not installed; the chart's `policies.kyverno.io` group cannot
  be trimmed (its switches are ignored in 3.9.1), so 18 CRDs and 2.5 MiB of schema come with it,
  against 22 CRDs and 5.6 MiB by default.
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

One more component in the request path, and 2.5 MiB of CRD schema for the API server to hold (on
top of 48 CRDs and about 1.2 GiB). The install is measured on the running cluster (API server
memory, node memory, webhook latency) and the numbers are recorded here. Policies live in `kubernetes/platform/policies/kyverno/`. Uninstalling needs the
webhook configurations removed (the chart's pre-delete hook does it; whether Argo CD 3.5 runs
that hook has to be checked, and until then it is a manual step). Kyverno 1.19 is not documented
as tested on Kubernetes 1.37, like the other components (see `STATUS.md`).
