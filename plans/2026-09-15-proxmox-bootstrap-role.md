# 2026-09-15 — Proxmox bootstrap Ansible role

Goal: automate `docs/proxmox/installation.md`'s 4 manual post-install
steps (network check, firewall, API token, SSH key) via Ansible instead
of the Proxmox web UI, per user request ("pot sa fac 1,2,3,4 printr-un
script sau ceva automat?").

## Tasks

- [x] `ansible/inventories/production/hosts.example.yml` + `group_vars/proxmox.yml.example`
- [x] `ansible/ansible.cfg` (roles_path)
- [x] `ansible/playbooks/proxmox-bootstrap.yml` — staged, 6 tags, documented run order
- [x] `ansible/roles/proxmox_bootstrap/` — network_check (read-only), api_token (additive), ssh_key_add (additive), firewall_rules (additive, permissive), firewall_enforce (RISKY, `never` tag + interactive confirm), ssh_lockdown (RISKY, `never` tag + independent re-verification + interactive confirm)
- [x] `host.fw.j2` template, no extra Ansible collections (avoided `ansible.posix`/`community.general` deps deliberately)
- [x] `ansible-playbook --syntax-check` — pass (verified live in WSL2)
- [x] `ansible-lint` profile `production` — pass, 0 failures (verified live in WSL2; first run found 27 real findings — var-naming prefix, FQCN, line-length — all fixed, not suppressed)
- [x] `gitleaks` full-tree scan — no leaks
- [x] Docs: `ansible/README.md` rewritten (role description, WSL2/Windows-mount gotchas), `docs/proxmox/installation.md` linked to the role, `STATUS.md` updated with accurate IMPLEMENTED-but-not-deployed state and revised next-milestone sequence

## Safety design (why this isn't a single unattended script)

Two stages carry real lockout risk on a single physical host with no
other admin path (firewall policy, SSH password auth). Both are gated
behind Ansible's `never` tag (require explicit `--tags`, never run by a
broader/default invocation) AND an interactive `pause` confirmation AND,
for SSH lockdown specifically, an automated independent re-verification
of key-based login from the controller before touching `sshd_config`.
Firewall rules stage writes rules with `policy_in: ACCEPT` first (nothing
blocked) — only the separate `firewall_enforce` tag flips to `DROP`. This
was cross-checked against Proxmox's own documented anti-lockout behavior
(<https://pve.proxmox.com/wiki/Firewall>) rather than assumed.

## Environment findings worth keeping

- Ansible refuses to auto-load `ansible.cfg` from a WSL2 `/mnt/*` NTFS
  mount ("world writable directory") — needs `ANSIBLE_CONFIG=` set
  explicitly. Documented in `ansible/README.md`.
- `ansible-lint`'s YAML sub-rules conflict with the repo's `.yamllint.yaml`
  in a few opinionated ways (comment indentation, brace spacing, octals).
  Accepted as a known mismatch rather than weakening repo-wide yamllint
  config for ansible-lint's stricter subset. Only disables ansible-lint's
  own `-f` autofix; doesn't affect pass/fail.
- Non-interactive `wsl.exe -- bash -lc` doesn't reliably source the
  user's mise activation (their `.bashrc`/PATH setup has unrelated issues
  with space-containing Windows PATH entries) — `~/.local/bin/mise exec
  --` is the reliable way to invoke mise-managed tools non-interactively.

## Execution against the real host (2026-09-15, by the user)

All 6 stages run against `pve01`, in order, with manual verification
between the risky ones — **deployed and verified**, not just generated:

- `network_check`, `api_token`, `ssh_key_add` — ran cleanly.
- `firewall_rules` — failed first attempt: `ansible.builtin.template`
  can't write directly to `/etc/pve/nodes/<node>/host.fw` because
  `/etc/pve` is `pmxcfs`, a non-POSIX FUSE filesystem that rejects the
  `rename()`+`chmod()` the module uses internally
  (`[Errno 1] Operation not permitted`). Fixed by rendering to `/tmp`
  first, then `ansible.builtin.command: cp` into place (a plain
  open+write pmxcfs accepts) — applied to both `firewall_rules.yml` and
  `firewall_enforce.yml`. Confirmed against a known Ansible/Proxmox
  community issue (github.com/ansible/ansible/issues/70535), not guessed.
- `firewall_enforce` — ran cleanly after the fix, confirmed via interactive
  pause, host stayed reachable.
- `ssh_lockdown` — failed first attempt: the private-key path was derived
  from the public-key path via `regex_replace('\\.pub$', '')` inside a
  YAML `>-` folded block scalar — the escaping didn't survive the
  YAML-then-Jinja round trip in practice, so the task tried to use the
  `.pub` file itself as the SSH private key (surfaced as an "unprotected
  private key file" / bad-permissions error, not an obviously-wrong-path
  error, which made it worth documenting). Fixed by adding an explicit
  `proxmox_bootstrap_admin_ssh_privkey_path` default instead of deriving
  it — no regex, no ambiguity. Re-ran clean; the role's own independent
  key-login self-check passed before it touched `sshd_config`.
- User independently confirmed key-only SSH access from a fresh terminal
  after lockdown — verified, not just claimed.

Net result: `pve01` now has a dedicated least-privilege OpenTofu API
token, an admin SSH key, firewall rules (deny-by-default + explicit mgmt
allow), and password SSH auth disabled. `STATUS.md` updated to DEPLOYED
for both the Proxmox host and this role.

## What's still manual before Phase 1 continues

The OpenTofu API token was shown exactly once during `api_token` — confirm
it's stored somewhere durable (GitHub Actions Secrets / local secrets
manager) before starting the OpenTofu module work in `STATUS.md`'s next
milestone.
