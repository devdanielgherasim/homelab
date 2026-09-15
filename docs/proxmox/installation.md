# Proxmox VE Installation (Unavoidable Manual Procedure)

Status: **current state as of 2026-09-15** — Proxmox VE 9.2 is installed
bare-metal on the physical laptop using the standard ISO installer, at
installer defaults, with no further intentional configuration applied yet.
This is the project's clean starting point — see
[`STATUS.md`](../../STATUS.md).

## Why this step is manual and stays manual

The ISO installer is a one-time, interactive, hardware-level step (disk
partitioning, initial network interface, root credential) that runs before
any Git-managed automation can reach the machine — there is nothing for
OpenTofu or Ansible to configure yet at this point, because neither can
reach a host that doesn't exist and has no SSH/API access configured.
This is the **only** step in the recovery path that is not reproduced by
cloning this repository. Everything after it is.

## Responsibility model (where each layer of config actually lives)

```
Manual Proxmox ISO installation
        │
        └──▶ this document (docs/proxmox/installation.md)

Proxmox host configuration (firewall, users/API tokens, network bridges,
storage config, repo/updates)
        │
        └──▶ Ansible (ansible/ — targets the Proxmox host itself, not a guest)

Proxmox VM / infrastructure resources (VM definitions, disks, NICs)
        │
        └──▶ OpenTofu (tofu/ — via the Proxmox API, using credentials
             provided at runtime, never committed)

Guest operating-system configuration (packages, users, hardening,
containerd/kubeadm prerequisites)
        │
        └──▶ Ansible (ansible/ — targets the guest VMs)

Kubernetes bootstrap (kubeadm init/join)
        │
        └──▶ Ansible (ansible/ — orchestrates kubeadm; produces a cluster
             Argo CD can then take over)

Kubernetes platform desired state (CNI, ingress/mesh, observability,
policy, apps)
        │
        └──▶ Argo CD (kubernetes/platform/, kubernetes/apps/ — see
             docs/architecture/gitops.md)
```

**Rule:** once the Proxmox API is reachable (host installed, network
configured, an API token or SSH key provisioned), no further Proxmox host
or guest configuration happens by hand through the web UI. If a change is
needed, it goes into Ansible or OpenTofu and is applied from there — see
the destructive-action policy in [`../../AGENTS.md`](../../AGENTS.md) for
what still requires explicit human approval even when automated.

## What the manual installer step actually covers

Recorded here as the documented baseline, not as literal step-by-step
clicks (those are standard upstream Proxmox installer screens):

1. Boot the official Proxmox VE 9.2 ISO on the physical laptop.
2. Select the target disk (the laptop's Samsung SSD 870 EVO 500 GB).
3. Set the initial root password and admin email at the installer prompt
   — treated as a bootstrap credential, rotated/managed afterward per
   [`../security/public-repository.md`](../security/public-repository.md);
   never recorded in this repository.
4. Configure the initial management network interface on the private LAN
   management segment (see [`../architecture/networking.md`](../architecture/networking.md)
   for the addressing plan; the real assigned address is not published
   here per that document's policy).
5. Complete the install and reboot to the Proxmox web UI.

## What happens immediately after install, before any automation runs

These are the minimum manual actions needed to make the host reachable by
Ansible/OpenTofu — after this, the responsibility model above takes over:

1. Confirm the management network interface matches the documented
   addressing plan (`docs/architecture/networking.md`).
2. Enable the Proxmox firewall at the datacenter/node level (deny-by-
   default posture — see [`../security/threat-model.md`](../security/threat-model.md)).
   Fine-grained rules are then managed declaratively, not left as a manual
   one-off.
3. Create a dedicated API token (not the root account) for OpenTofu's
   Proxmox provider, scoped to only what VM provisioning requires. The
   token value is provided at runtime (environment variable or a local,
   gitignored file) — never committed. See
   [`../security/public-repository.md`](../security/public-repository.md#secret-handling).
4. Provision or confirm SSH key-based access for Ansible (Ed25519, no
   password auth) to the Proxmox host itself.

Once steps 1–4 are done, the host is a target for `tofu`/`ansible`, not a
UI to click through. **None of steps 1–4 have been performed yet as of
this document's last update** — see [`STATUS.md`](../../STATUS.md).

## Reproducibility / disaster-recovery objective

```
fresh Proxmox installation (this document)
        │
        ▼
clone repository
        │
        ▼
provide private runtime configuration/secrets (local/, GitHub Secrets)
        │
        ▼
bootstrap (steps 1–4 above, plus Ansible host-config run)
        │
        ▼
recreate infrastructure (tofu apply — provisions vpn01/cp01/worker01/worker02)
        │
        ▼
recreate Kubernetes (Ansible: kubeadm init/join)
        │
        ▼
recreate platform (Argo CD reconciles kubernetes/platform/ + kubernetes/apps/)
```

A fork of this repository should be able to follow this same path with
its own environment values substituted in — see
[`../contributing/development-workflow.md`](../contributing/development-workflow.md).
Only the box at the top of this diagram is manual; everything below it is
declared in Git.

## Configuration drift detection (design)

Once Ansible/OpenTofu manage the host, drift between the declared state in
Git and the actual host is detected, not silently tolerated:

- `tofu plan -detailed-exitcode` against `tofu/environments/` reports
  infrastructure-level drift (exit code `2` = drift present) without
  applying anything.
- `ansible-playbook --check --diff` against `ansible/playbooks/` reports
  configuration-level drift the same way.

Both are non-mutating by design and safe to run on a schedule once real
infrastructure exists; wired as `make drift` (see `Makefile`) once
`tofu/` and `ansible/` hold real content — not implemented during
repository bootstrap, since there is no host to check yet.
