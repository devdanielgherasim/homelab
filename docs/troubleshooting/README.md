# Troubleshooting

Entries recorded here are from **real incidents actually encountered and
resolved** in this lab — not hypothetical failure modes. Speculative
troubleshooting content belongs in
[`../architecture/infrastructure.md`](../architecture/infrastructure.md#failure-scenarios-to-practice)
as a scenario to practice, not here as a resolved incident.

## Format

Each entry (`docs/troubleshooting/<slug>.md`):

1. **Symptom** — what was observed.
2. **Diagnosis** — how the cause was found (commands, signals).
3. **Root cause**.
4. **Fix**.
5. **Prevention** — what changed so it doesn't recur (a Kyverno policy, an
   alert, a doc update).

## Current entries

| Entry | Area | One-line summary |
|---|---|---|
| [`proxmox-api-token-403-privsep.md`](proxmox-api-token-403-privsep.md) | Proxmox RBAC / OpenTofu | Token with `--privsep 1` has the intersection of user and token ACLs; three separate 403s on clone |
| [`pmxcfs-template-not-permitted.md`](pmxcfs-template-not-permitted.md) | Proxmox / Ansible | `template` cannot write to `/etc/pve` (pmxcfs); render to `/tmp`, then `cp` |
| [`containerd-cri-disabled-by-package.md`](containerd-cri-disabled-by-package.md) | Kubernetes bootstrap | `containerd.io` ships `disabled_plugins = ["cri"]`; `kubeadm init` fails preflight |
| [`ansible-derived-private-key-path.md`](ansible-derived-private-key-path.md) | Ansible | A regex-derived key path silently pointed at the `.pub` file |
