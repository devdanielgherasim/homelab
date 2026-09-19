# 0002. Ubuntu Server 24.04 LTS as guest OS

Status: Accepted
Date: 2026-09-15

## Context

All Proxmox guest VMs (`vpn01`, `cp01`, `worker01`, `worker02`) need a
consistent Linux distribution suited to running `kubeadm` + containerd,
with long-term support and wide community/documentation coverage for
troubleshooting.

## Decision

Use Ubuntu Server 24.04 LTS, no desktop environment, as the guest OS for
every VM in the lab.

## Alternatives considered

- **Debian** — also viable and closer to some production environments, but
  Ubuntu's LTS cadence and broader up-to-date package/driver support was
  judged simpler for a single maintainer.
- **A minimal/immutable OS (Talos, Flatcar)** — attractive long-term, but
  removes the general Linux administration surface (SSH, systemd,
  troubleshooting a normal init system) that is itself a learning goal
  here.
- **Mixed distros per node** — rejected for operational consistency;
  Ansible roles would need to branch per distro for no real benefit.

## Consequences

One Ansible role family, one patching cadence, one set of package manager
assumptions across the fleet. Revisit if a specific node's role (e.g. a
future immutable-runner experiment) needs a different base.
