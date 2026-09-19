# Cilium (CNI)

Cilium is installed with Helm during cluster bootstrap, before Argo CD exists
(a GitOps controller cannot install the network it needs to run on). Whether
Argo CD later takes over managing it from this same values file is not decided
yet — see [`../../../docs/architecture/gitops.md`](../../../docs/architecture/gitops.md).

- Chart: `cilium/cilium` **1.20.2** from `https://helm.cilium.io`.
- Values: [`values.yaml`](values.yaml). Every key was checked against
  `helm show values cilium/cilium --version 1.20.2`.
- Design rationale: [ADR-0005](../../../docs/adr/0005-cilium-as-cni.md).

## Version support deviation

Cilium 1.20.2's compatibility table lists Kubernetes **1.33–1.36** as tested.
This cluster runs Kubernetes **1.37.0**, one minor version newer than
anything upstream has tested with a released Cilium. It was installed anyway
because 1.20.2 is the newest stable release, and the result was verified
with `cilium connectivity test` (see [Verification](#verification)). Re-check
the compatibility table when a Cilium release lists 1.37.

## What the values choose, and why

| Setting | Value | Reason |
|---|---|---|
| `kubeProxyReplacement` | `true` | Cilium's eBPF datapath replaces `kube-proxy`. |
| `ipam.mode` | `cluster-pool`, `10.244.0.0/16`, /24 per node | Matches `--pod-network-cidr` in `ansible/roles/kubeadm_init`. |
| `operator.replicas` | `1` | One control-plane node; the default of 2 would leave a pod `Pending`. |
| `envoy.enabled` | `false` | Envoy is one extra pod per node and only serves L7 features; north-south traffic goes through Istio (ADR-0006). |
| Hubble | relay and UI on | Flow visibility is the main learning tool for NetworkPolicy work. |
| Resource limits | set on every component | Nodes have about 3 GB of RAM; the observability stack still has to fit. |

`k8sServiceHost` is deliberately **not** in the file. It is the control-plane
address of this lab, which is network topology that stays out of a public
repository, so it is passed at install time.

## Install

Prerequisites: a cluster without a CNI, `kubectl` and `helm` pointed at it.

```bash
helm repo add cilium https://helm.cilium.io && helm repo update cilium

# Only when kube-proxy is already installed (fresh clusters should be
# created with `kubeadm init --skip-phases=addon/kube-proxy` instead):
kubectl -n kube-system delete ds kube-proxy
kubectl -n kube-system delete cm kube-proxy
# then, on every node, remove its leftover rules:
#   sudo sh -c 'iptables-save | grep -v KUBE | iptables-restore'

helm upgrade --install cilium cilium/cilium --version 1.20.2 \
  --namespace kube-system \
  -f kubernetes/bootstrap/cilium/values.yaml \
  --set k8sServiceHost=<control-plane-ip> \
  --wait --timeout 10m
```

## Verification

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
  cilium-dbg status --verbose | grep KubeProxyReplacement   # -> True
cilium status --wait
cilium connectivity test
```

Result on 2026-09-19 (Kubernetes 1.37.0, three nodes, Ubuntu 24.04, kernel 6.8):

- `KubeProxyReplacement: True`; `cilium status` reports Cilium, Operator and
  Hubble Relay `OK`, 3/3 agents ready, cluster health `3/3 reachable`.
- All three nodes `Ready`, CoreDNS running, no pod outside `Running`.
- `cilium connectivity test` (CLI v0.20.0): **82 tests (707 actions)
  successful, 55 skipped, 0 failed.** Skips are tests that modify node state
  ("unsafe"), features not enabled here (ingress controller, mutual auth,
  Envoy config, local redirect policy) and Cilium-version conditions. Those
  areas are untested rather than passed.
- The test leaves `cilium-test-*` namespaces behind; delete them afterwards.

## Rollback

`helm uninstall cilium -n kube-system`, then recreate kube-proxy on the
control plane with `kubeadm init phase addon kube-proxy` (with the same
`--pod-network-cidr` and `--apiserver-advertise-address` used at init). The
nodes return to `NotReady`, which is the state before a CNI exists. This path
has **not been exercised**. Proxmox snapshots of the three nodes (`pre-cilium`)
were taken before the install as a fallback; restoring them has not been
tested either.

## Known follow-ups

- Hubble Relay's server TLS is off (Helm prints a warning). It is only
  reachable inside the cluster, but enabling
  `hubble.relay.tls.server.enabled` is on the hardening list.
- Hubble metrics are disabled until the observability stack (phase 8) exists.
