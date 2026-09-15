# ansible/

Ansible configuration for everything that isn't Proxmox VM *creation*
(that's `tofu/`) or Kubernetes platform state (that's Argo CD):

- Proxmox host configuration (firewall, users/API tokens, network,
  storage, updates).
- Guest OS configuration (packages, users, SSH hardening, containerd/
  kubeadm prerequisites).
- Kubernetes bootstrap (`kubeadm init`/`join`).

See [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md)
for the full responsibility model and
[`../docs/architecture/infrastructure.md`](../docs/architecture/infrastructure.md)
for sizing/context.

## Layout (created as content lands, not pre-scaffolded)

```
ansible/
├── inventories/   # real inventory is gitignored; commit *.example only
├── playbooks/      # e.g. proxmox-host.yml, guest-base.yml, kubeadm-bootstrap.yml
└── roles/
```

## Rules

- Real inventory files, vault passwords, and any host-specific variables
  with real values are never committed — see `.gitignore` and
  [`../docs/security/public-repository.md`](../docs/security/public-repository.md).
- Playbooks that touch the real Proxmox host or a real cluster are never
  run by an agent or a hook without explicit human approval — see
  [`../AGENTS.md`](../AGENTS.md#destructive-action-policy).
- `ansible-lint` and `ansible-playbook --syntax-check` must pass before
  commit — enforced in CI.
- `ansible-playbook --check --diff` is the drift-detection mechanism once
  real playbooks exist (see
  [`../docs/proxmox/installation.md`](../docs/proxmox/installation.md#configuration-drift-detection-design)).

## Status

No playbooks exist yet — see [`../STATUS.md`](../STATUS.md).
