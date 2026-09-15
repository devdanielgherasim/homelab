# 2026-09-16 — Guest OS hardening (all 4 VMs)

Goal: harden `vpn01`/`cp01`/`worker01`/`worker02` beyond the template's
cloud-init defaults, per `docs/architecture/networking.md`'s "SSH Ed25519
keys; disable password authentication and direct root login on guest
VMs" and `docs/security/threat-model.md`.

## Scope decisions

- **In scope**: explicit SSH hardening (defense in depth — cloud-init
  already sets the `ubuntu` user up key-only with no password, so this
  closes a door that likely doesn't open anyway, rather than removing a
  functioning access path); unattended security upgrades, no automatic
  reboot (a silent reboot on a homelab node you might be mid-task on is
  its own kind of surprise — reboot cadence stays a human decision).
- **Explicitly deferred, not this role**: `ufw`/guest firewall (the
  Proxmox host firewall + future Cilium NetworkPolicies are the intended
  layers per the architecture, not a third guest-level firewall — avoids
  tool sprawl for unclear benefit); swap-disable (a kubeadm prerequisite,
  not a hardening concern — belongs in the next role); fail2ban (LAN-only,
  key-only SSH already; no clear benefit here, project principle against
  tools without a clear purpose).
- **Risk profile, why this role skips the `proxmox_bootstrap`-style
  never-tag/interactive-pause treatment**: that pattern existed because
  `ssh_lockdown` on the Proxmox host was removing a *functioning*
  password-based access path. Here, cloud-init never set a password for
  `ubuntu` in the first place — there's no working access path being
  removed, only a defense-in-depth config explicit-ized. Still verified
  with `sshd -t` before restart.

## Tasks

- [x] `ansible/inventories/production/hosts.example.yml` — added a
      `homelab_vms` group (vpn01/cp01/worker01/worker02, `ansible_user: ubuntu`)
- [x] `ansible/roles/guest_hardening/` — ssh_hardening, unattended_upgrades
- [x] `ansible/playbooks/guest-hardening.yml`
- [x] `ansible-lint` (production profile) — pass; caught and fixed a real
      YAML parse error along the way (an unquoted task name containing
      `(default: no silent reboot)` — the colon-space mid-plain-scalar
      broke YAML parsing, not an ansible-lint style nitpick)
- [x] `--syntax-check` — pass
- [x] `gitleaks` — clean
- [x] Docs: `ansible/README.md` updated
- [ ] User runs it against the real 4 VMs
