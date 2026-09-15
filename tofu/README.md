# tofu/

OpenTofu configuration for Proxmox VM/infrastructure resources — VM
definitions, disks, NICs, cloud-init. See
[`../docs/architecture/infrastructure.md`](../docs/architecture/infrastructure.md)
and [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md)
for the full responsibility model (this directory does **not** own Proxmox
host-level configuration — that's Ansible).

## Layout (created as content lands, not pre-scaffolded)

```
tofu/
├── modules/        # reusable OpenTofu modules (e.g. a "proxmox-vm" module)
└── environments/   # per-environment root modules (e.g. homelab/)
```

## Rules

- State is never committed — see `.gitignore` and
  [`../docs/security/public-repository.md`](../docs/security/public-repository.md#opentofu-state).
- Real variable values (`terraform.tfvars`) are never committed; only
  `terraform.tfvars.example` with placeholder values is.
- `tofu apply` / `tofu destroy` are never run by an agent or a hook without
  explicit human approval — see
  [`../AGENTS.md`](../AGENTS.md#destructive-action-policy).
- `tofu fmt -check -recursive && tofu validate` must pass before commit —
  enforced in CI (`.github/workflows/validate.yml`).

## Status

No modules exist yet — see [`../STATUS.md`](../STATUS.md).
