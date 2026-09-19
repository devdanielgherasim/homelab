# 0001. Proxmox VE as hypervisor

Status: Accepted
Date: 2026-09-15

## Context

A single laptop (~16 GB RAM) needs to host multiple VMs (VPN gateway,
Kubernetes control plane, two workers) as if it were a small production
fleet, for DevOps/Platform Engineering learning and portfolio purposes.
The hypervisor needs a real firewall, snapshotting, and VM lifecycle
management, and should itself be a realistic, industry-relevant choice.

## Decision

Use Proxmox VE, installed bare-metal on the laptop, as the hypervisor for
all lab VMs.

## Alternatives considered

- **VirtualBox / VMware Workstation on a host OS** — adds a host-OS layer
  of overhead and doesn't model a realistic bare-metal virtualization
  platform used in industry.
- **libvirt/KVM directly** — more manual than needed; loses the built-in
  firewall, backup, and web UI that make day-to-day lab operation practical
  on limited hardware.
- **A public cloud instead of a laptop** — defeats the zero-recurring-cost
  and "own the whole stack, including the hypervisor" learning goals.

## Consequences

Gains a realistic virtualization/firewall/snapshot layer and Proxmox-
specific operational experience. The laptop remains a single point of
failure regardless of hypervisor choice — accepted, documented in
[`../architecture/overview.md`](../architecture/overview.md). Repository
layout follows Proxmox's conceptual model (VMs, not containers) at the
infrastructure layer — see [`../architecture/infrastructure.md`](../architecture/infrastructure.md).
