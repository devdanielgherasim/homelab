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

Three more values were added for the LoadBalancer (ADR-0015) and the service mesh
(ADR-0006): `l2announcements.enabled`, `socketLB.hostNamespaceOnly` (socket-level load
balancing conflicts with Istio's traffic redirection inside pods) and `cni.exclusive:
false` (istio-cni chains its own configuration, which Cilium must not delete).

**After an upgrade that changes the ConfigMap, restart the agents**
(`kubectl -n kube-system rollout restart ds/cilium`). Helm does not do it, and the agents
keep the old setting; the log line `Mismatch found` from the config drift checker shows it.
The chart does it itself with `rollOutCiliumPods: true` (checked in `helm show values` for
1.20.2), which is now set: the agents carry a checksum of the ConfigMap as an annotation.

## Install

Cilium is installed by the platform stage, not by hand
([ADR-0016](../../../docs/adr/0016-platform-bootstrap-with-opentofu.md)):
[`tofu/environments/platform/cilium.tf`](../../../tofu/environments/platform/cilium.tf) is a
`helm_release` of chart 1.20.2 with the values file in this directory. The API server address
(`k8sServiceHost`, network topology) comes from the private `terraform.tfvars`, so it is never
committed. Read the plan before applying: Cilium is the cluster's network, and the release is
`atomic`, so a failed upgrade rolls itself back.

```bash
cd tofu/environments/platform
tofu plan && tofu apply
```

The cluster must have been created without kube-proxy (`kubeadm init
--skip-phases=addon/kube-proxy`, which `ansible/roles/kubeadm_init` does). On a cluster that still
has it, remove it first: delete the `kube-proxy` DaemonSet and ConfigMap in `kube-system` and, on
every node, its leftover rules (`sudo sh -c 'iptables-save | grep -v KUBE | iptables-restore'`).

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

- Hubble Relay's server TLS is on (ADR-0013); mutual TLS is off so the UI can connect.
- Metrics: the endpoints and the Grafana dashboards are on in these values, and the scrape
  configuration (`PodMonitor`s) is in `kubernetes/platform/observability/monitors/`. The chart's
  own `ServiceMonitor`s stay off because this chart is installed before the Prometheus Operator's
  CRDs exist. `rollOutCiliumPods` and `operator.rollOutPods` are on, so a ConfigMap change restarts
  the agents by itself.
