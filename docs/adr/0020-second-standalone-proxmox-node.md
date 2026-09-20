# 0020. A second Proxmox node, standalone, with the workers placed per node

Status: Proposed
Date: 2026-09-20

## Context

The whole lab ran on one Proxmox host (the laptop), and its memory had become the limit: after
Kyverno the control plane used 74% of 4 GiB, the host had about 2 GiB left, and nothing that
needs memory could grow (ADR-0019 has the measurement). The owner has a spare PC (Intel Core
i5-3470S, 4 cores, 8 GB DDR3, SSD) and switches both machines on only while working.

Two things follow from that hardware and that habit. The second machine is an older CPU (Ivy
Bridge, 2012: AES-NI and SSE4.2, no AVX2), and either machine may be off, so neither may be
needed for the other to boot.

## Decision

Install Proxmox VE on the second machine as its own **standalone node**, not as a cluster, and
let OpenTofu place each worker on a node.

- **No Proxmox cluster.** A two-node cluster loses quorum whenever one node is off, and here that
  is normal: the surviving node would refuse to start or change VMs until quorum is forced.
  Standalone nodes have no such coupling. What is given up is live migration and a single
  management view; a VM is moved by rebuilding it, which fits workers that hold no state and
  are rebuilt from Git anyway.
- **One OpenTofu state, two providers.** `secondary_proxmox` (node name and API endpoint) and its
  token (`TF_VAR_secondary_proxmox_api_token`, from the environment) configure a second provider
  alias. A provider cannot be chosen per `for_each` item, so the workers on the second node are
  a second call of the same module (`workers_secondary`), and a worker chooses its node with
  `node = "pve02"`. Unset means the first node, so a single-host lab changes nothing (the plan
  for that case was checked to be identical, the state addresses included).
- **A fixed CPU type on the second node.** The VM module used `host` on the reasoning that there
  was one physical host. Workers on the older node get `x86-64-v2-AES`, so what runs in them does
  not depend on features the newer CPU has; the first node keeps `host`.
- **Each node has its own CA**, so `SSL_CERT_FILE` points at a bundle of both. The bootstrap role
  saves one CA file per host and rebuilds the bundle.
- **Ansible acts per node.** The generated inventory carries `proxmox_host` for every VM, and the
  roles that work on a Proxmox host (`proxmox_vm_startup`, `proxmox_backup`) touch only the VMs on
  that host. The bootstrap role's pool step only adds VMs that exist on the host it runs on.
- **`worker02` keeps its name, VMID and address** and moves; `cp01` stays where it is and gets the
  memory that the move frees.

## Alternatives considered

- **A Proxmox cluster with a quorum device (QDevice).** Gives migration and one UI, but needs a
  third always-on machine, which this lab does not have.
- **A cluster with `expected votes = 1`.** Works around quorum by hand each time a node is off;
  a bootstrap that depends on a manual override is what this repository avoids.
- **Buying more RAM for the first host.** The laptop's memory is fixed.
- **The Windows PC as a Proxmox node** (nested, or Docker). Out of scope for now, by the owner's decision;
  the same design would take a third node.

## Consequences

The lab has two failure domains and a worker on each. While one machine is off the cluster is
degraded, not down: the control plane and the worker on the first node keep serving, and pods
that have to move do so within the memory of what is left. Backups of `cp01` stay on the first node
only (ADR-0012); the second node holds a worker and has no job.

The Kubernetes network crosses two physical machines that share a LAN segment: pod traffic between
workers now goes over the switch, not a bridge. That is the first time the lab depends on
the LAN for the cluster, and it is exactly what a real cluster does.

Costs: two Proxmox hosts to keep patched, each with its own token and firewall, and a bootstrap
that has to be run once per node. The firewall role has a defect found on the way, which
is not part of this decision: `policy_in` and `policy_out` are written to `host.fw`, where Proxmox
does not accept them (they belong to `cluster.fw`), on both nodes.
