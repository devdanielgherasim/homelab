# 0015. LoadBalancer addresses from Cilium (LB IPAM + L2 announcements), not MetalLB

Status: Accepted
Date: 2026-09-20

## Context

A `Service` of type LoadBalancer needs something on bare metal to hand out an address
and to make it reachable. The design listed MetalLB for this
([`../architecture/kubernetes.md`](../architecture/kubernetes.md)). The cluster already
runs Cilium with kube-proxy replacement, which can do the same job natively, and there
is about 5 GB of free RAM for the whole platform.

## Decision

Use **Cilium LB IPAM and L2 announcements**. A `CiliumLoadBalancerIPPool` defines the
addresses; a `CiliumL2AnnouncementPolicy` selects the Services and nodes that answer ARP.
Both are selected by the label `homelab.io/lb-pool: private`, so only the Gateway's
Service receives an address. The pool holds real LAN addresses and is applied from a
private inventory (`ansible/roles/cilium_lb_pool`); the policy has no addresses and is
in Git (`kubernetes/platform/networking/`).

## Alternatives considered

- **MetalLB (L2 mode).** Mature and independent of the CNI agent. It adds a controller
  and a speaker on every node (with an frr-k8s DaemonSet by default in the 0.16 chart,
  to be switched off) and needs a privileged namespace. Its L2 mode has the same
  one-node-per-address limit as Cilium's. It would be the choice if Cilium's feature
  proved unreliable.
- **Both together.** Not supported: two announcers for one address.

## Consequences

No new component and no extra RAM. L2 announcements are still labelled **Beta** in the
Cilium 1.20 documentation, so this is the least mature part of the stack. Failover when
the announcing node dies takes 10-20 seconds (leader election through a Lease), one node
carries all traffic for an address, and the feature is incompatible with
`externalTrafficPolicy: Local` (the Gateway's Service uses the default). If the Cilium
agent on the announcing node is down, that node stops announcing. Cilium 1.20 lists
Kubernetes 1.33-1.36 as tested; this cluster runs 1.37 (see ADR-0005).

Enabling it changes Cilium's Helm values (a rolling restart of the agents) together with
two settings the service mesh needs (`socketLB.hostNamespaceOnly`, `cni.exclusive: false`).

Accepted on 2026-09-20 after a test on the cluster: a temporary `LoadBalancer` Service
received the first address of the pool, the Lease `cilium-l2announce-demo-lb-test` was
taken by `worker01` (the control plane is excluded by the policy), and the sample app
answered on that address from the Windows PC on the LAN. The Service and the Lease
disappeared together after the test.

Lesson from the rollout: `helm upgrade` changes the Cilium ConfigMap but does not restart
the agents. They kept running with `enable-l2-announcements=false` and logged
`Mismatch found ... key=enable-l2-announcements` (the config drift checker) until
`kubectl -n kube-system rollout restart ds/cilium` was run. The address was assigned
(that is the operator) but nothing answered ARP. After the restart the warnings were gone.
