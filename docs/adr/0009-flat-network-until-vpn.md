# 0009. Single flat network until the VPN and segmentation exist

Status: Accepted
Date: 2026-09-19

## Context

[`networking.md`](../architecture/networking.md) targets separate management,
Kubernetes node and load-balancer networks. The physical host has one bridge
(`vmbr0`) attached to the household LAN, and the VPN gateway (`vpn01`) is not
configured yet. Building Kubernetes on top of a segmented network before the
remote-access path works would make every failure harder to diagnose and
could lock the operator out of the host.

## Decision

Place all four VMs on `vmbr0`, on the same layer-2 network as the household
LAN, with static addresses managed in a private inventory. Treat this as a
temporary, explicitly recorded deviation, not as the design. Segmentation and
VPN-only access remain targets (phases 2 and 4-5 of the roadmap).

## Alternatives considered

- **Segment first (VLANs or a second bridge)** — closer to the target, but it
  needs router or switch support, and a mistake cuts off the only management
  path to a single-host lab.
- **Nested NAT network behind `vpn01`** — adds a routing dependency on a VM
  that is not configured yet.

## Consequences

The Proxmox UI, SSH and the Kubernetes API are reachable from the household
LAN until the VPN exists and the Proxmox firewall rules are narrowed to it.
The Proxmox host firewall already limits SSH and the web UI to the management
CIDR and drops other inbound traffic. The deviation is listed in
[`STATUS.md`](../../STATUS.md#known-deviations-from-the-target-design) and must
be closed before any workload or ingress is published. Superseded when
segmentation is implemented.
