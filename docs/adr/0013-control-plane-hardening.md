# 0013. Control-plane hardening, and what is deliberately left out

Status: Accepted
Date: 2026-09-19

## Context

A CIS Kubernetes Benchmark scan (kube-bench 0.16.0, benchmark `cis-1.12`) of the
freshly bootstrapped control plane gave 62 passes and 13 failures. The failures
were fixable defaults of a stock `kubeadm` cluster: no audit log, profiling
endpoints on, Secrets stored unencrypted in etcd, kubelet files readable by
everyone. Pod Security admission was also at its permissive default. The cluster
had been created with command-line flags, so the resulting configuration was not
written down anywhere.

## Decision

- **One declarative source.** `ansible/roles/kubeadm_init` renders a
  `kubeadm-config.yaml` (kubeadm `v1beta4`, based on the live cluster's own
  `ClusterConfiguration`). It is used by `kubeadm init --config` for a new
  cluster and applied to a running one with `kubeadm init phase control-plane
  all`, so a rebuild and the live cluster share one definition.
- **Encryption at rest** for Secrets with the `secretbox` provider (the
  recommended local provider; `aescbc` is discouraged upstream), with `identity`
  kept as a fallback reader. The key is generated on the control-plane node, is
  never in Git and is never rotated implicitly. It is included in the etcd
  backup archive, because a restored snapshot is unreadable without it.
- **Audit logging** with a policy that records who changed access control and
  who reached into pods, keeps Secret and ConfigMap requests at metadata level
  (no bodies), and drops health checks, events and lease traffic.
- **Pod Security admission defaults:** `enforce: baseline`, `warn` and `audit`
  at `restricted`, with `kube-system` exempt. Namespaces that need more (a load
  balancer, a service mesh) opt in with an explicit label instead of a wider
  default.
- **Profiling off** on the API server, controller manager and scheduler, service
  account token expiry not extended, and the kubelet and etcd files restricted
  (mode 600, etcd data owned by an `etcd` account).
- **Reversible rollout.** The role backs up the manifests, regenerates the
  control plane, and if the API server does not come back restores the old
  manifests automatically. That rollback stops at the moment Secrets are
  re-encrypted, because from then on an API server without the key could not
  read them. Encryption is then proven by reading a Secret straight from etcd.

Result after applying it to the live cluster: 76 passes and 2 failures (see
[`../security/cis-benchmark.md`](../security/cis-benchmark.md)).

## Left out on purpose

- **CIS 1.2.5** (`--kubelet-certificate-authority`). *Update 2026-09-20: the kubelet
  serving certificates and the approver now exist, see ADR-0018; only the API server flag
  is left.* It needed kubelet serving
  certificates signed by the cluster CA, which means `serverTLSBootstrapping`
  plus something to approve the resulting certificate requests, including the
  yearly renewals. That is one more component to run; it is revisited when the
  platform is managed through GitOps.
- **CIS 4.3.1** checks kube-proxy, which Cilium replaced. It does not apply.
- **A stable control-plane endpoint** (`controlPlaneEndpoint`) is supported by the
  role but empty, because it is cheap to set before the first init and costly to
  change afterwards, and there is a single control plane.
- **The 53 manual (WARN) checks**, mostly policy and workload topics (network
  policies, RBAC review, image provenance). They are tracked as work for the
  platform layer, not claimed as done.

## Consequences

Workloads in a new namespace must satisfy the `baseline` Pod Security level, or
the namespace must carry an explicit label. The Cilium connectivity test, for
example, needs its `cilium-test-*` namespaces labelled `privileged`. The API
server restarts whenever the control-plane configuration changes, so a change is
a short, planned interruption of the API (workloads keep running).

Losing the encryption key loses every Secret in a restored snapshot. The key is
therefore part of the backup and must be treated with the same care as the etcd
snapshot itself; both sit on the same disk (ADR-0012), and this is the reason
that decision matters more than before.
