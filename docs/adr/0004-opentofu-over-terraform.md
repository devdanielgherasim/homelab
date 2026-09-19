# 0004. OpenTofu instead of Terraform

Status: Accepted
Date: 2026-09-15

## Context

Proxmox VM provisioning needs a declarative IaC tool. HashiCorp Terraform
and its fork OpenTofu are functionally close and share HCL syntax and
provider ecosystems.

## Decision

Use OpenTofu for all IaC in this repository (`tofu/`).

## Alternatives considered

- **Terraform** — mature and has a Proxmox provider, but its license (BSL)
  is a proprietary vendor dependency the project principles explicitly
  avoid ("OpenTofu instead of proprietary IaC dependency" is a stated
  design goal, not just a preference). `terraform` is already installed on
  this machine and may remain useful for ad hoc comparison, but is not the
  repository's tool of record.
- **Pulumi** — general-purpose language-based IaC; steeper learning curve
  and less alignment with the HCL-based conventions used across the wider
  homelab/DevOps ecosystem this project is meant to demonstrate fluency in.
- **Ansible alone (no IaC layer)** — Ansible is better suited to
  configuration management than declarative resource lifecycle/state; VM
  creation specifically benefits from Terraform-style plan/apply and state.

## Consequences

OpenTofu is a near-drop-in for Terraform HCL and providers, so this
decision is low-risk to reverse later if needed. State handling (never
committed — see [`../security/public-repository.md`](../security/public-repository.md#opentofu-state))
applies identically either way.
