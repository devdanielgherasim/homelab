# Public Repository Security

This repository is public (or intended to become public). Assume every
committed file is visible to anyone on the Internet, indefinitely — Git
history included. This document is the threat model and the rules that
follow from it. It contains no secrets, real credentials, or real network
identifiers itself.

## Threat model

**What's being protected:** the private homelab (Proxmox host, VMs, VPN,
Kubernetes cluster) that this public repository documents and automates.
**What's public:** all source, documentation, CI configuration, and Git
history.

**Primary risks specific to a public IaC/GitOps repo:**

1. A secret gets committed (even briefly) and is scraped by an automated
   crawler before anyone notices — Git history preserves it regardless of
   later deletion.
2. A public pull request runs untrusted code with access to real
   credentials or a privileged self-hosted runner (see
   [`self-hosted-runners.md`](self-hosted-runners.md)).
3. Enough real network/hardware detail accumulates across files
   (router model, real LAN CIDR, public IP, DDNS name, MAC addresses,
   hardware serials, Tailscale node identities) that the home network
   becomes a more specific target than "a home router somewhere."
4. CI logs leak a credential or internal detail via verbose output.

**Out of scope:** general web-app security (this repo has no public web
app), physical security of the laptop.

## Secret handling

Never committed, under any circumstances, encrypted or not until reviewed
below: passwords, GitHub/Proxmox/registry tokens, Tailscale auth keys,
SSH/age/TLS private keys, kubeconfigs with embedded credentials,
Kubernetes service-account tokens, Ansible Vault passwords, OpenTofu state
or plan files, `.env` files with real values, backup files containing
credentials. Full pattern list enforced by `.gitignore` and `gitleaks`
(`.gitleaks.toml`) — see [`../../AGENTS.md`](../../AGENTS.md#secrets).

**Three-tier separation:**

| Tier | Example | Where it lives |
|---|---|---|
| Public reusable config | `terraform.tfvars.example`, `inventory.example.yaml`, roles, manifests | Committed |
| Private runtime config | real inventory, real `tfvars`, real kubeconfig | `local/` (gitignored), never committed |
| Secrets | Proxmox API token, Tailscale auth key, registry credentials | GitHub Actions Secrets, Ansible Vault, or runtime env — never Git |

**SOPS + age status:** listed in the target architecture
([`../architecture/overview.md`](../architecture/overview.md)) but **not yet
adopted as a committed pattern.** Encrypting a secret does not make it safe
to publish by default — key handling, rotation, and what happens if the
age private key itself leaks all need a specific plan for a public repo
before this becomes routine. Tracked as a pending ADR; until accepted,
secrets go through GitHub Actions Secrets / Ansible Vault (password not in
Git) / runtime env only.

## Network information policy

Documentation uses planning/example CIDRs
([`../architecture/networking.md`](../architecture/networking.md)), not the
real home LAN. **Never published** in this repository: the real home LAN
CIDR, public IP address, DDNS hostname, ISP identity, router make/model,
device MAC addresses, hardware serial numbers, or Tailscale node/device
identities. RFC 1918 private addresses used for the lab's *planned*
internal networks (management, node, pod, service CIDRs) are not
credentials and are published, because the project should be reproducible
through configuration — but they are never tied to the real household
network's actual addressing in this repo.

## Self-hosted runner trust boundary

See [`self-hosted-runners.md`](self-hosted-runners.md) in full. Summary:
public PR validation (lint, fmt, static analysis, security scan) always
runs on **GitHub-hosted runners** with `contents: read` and no homelab
credentials. Only trusted branches or explicitly authorized, manually
dispatched workflows may target the self-hosted runner, and even then with
least-privilege scope per job.

## Contribution security

External contributions (issues, PRs) are welcome but untrusted by default.
A maintainer reviews a first-time contributor's PR diff before any
workflow with elevated permissions runs against it. `pull_request_target`
and `workflow_run` triggers are treated as privileged and are reviewed
individually — see [`self-hosted-runners.md`](self-hosted-runners.md).

## CI log exposure

CI output is effectively public. Workflows must never print full
environments, credentials, kubeconfigs, tokens, sensitive Ansible
variables, or OpenTofu state. Use GitHub's secret masking; avoid `-vvv`
Ansible verbosity with secret-bearing variables and any full-environment
dump command.

## Incident procedure for a leaked secret

See [`../../SECURITY.md`](../../SECURITY.md#if-a-real-secret-is-ever-committed-to-this-repository)
for the full procedure: rotate first, clean history second, document the
incident without reproducing the secret.

## Agent rule

Every AI agent working in this repository must assume **"anything I write
here may become public."** Before creating or modifying a file, consider
whether the content could reveal credentials, private infrastructure
detail, personal information, sensitive network information, or internal
identifiers. When uncertain, use a configuration variable and a `.example`
file instead of a real value. This rule is also stated in
[`../../AGENTS.md`](../../AGENTS.md#public-by-default-rule); it is repeated
here because this is the canonical document for *why*.
