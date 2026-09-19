# AGENTS.md

Normative, provider-neutral instructions for any AI agent working in this
repository (Claude Code, Codex, or otherwise). Tool-specific instructions
(`CLAUDE.md`) may add routing on top of this file but must not contradict it.

**Authority order** (highest wins): repository code/config → `docs/adr/` →
`docs/` → this file → tool-specific instructions → agent/skill prompts.
If two sources disagree, the higher one is correct; fix the lower one.

## What this project is

A production-style Kubernetes homelab (Proxmox → kubeadm → Cilium → Istio →
Argo CD) built for DevOps/Platform Engineering learning and as a portfolio
reference. See `docs/architecture/overview.md` for the full design.
**The Proxmox host, four VMs and a 3-node kubeadm cluster exist; the platform
layer (CNI, ingress, GitOps, observability) is not built yet.** `STATUS.md`
is the only authority on what is running — check it before claiming anything
works.

## Repository map — read the doc, not the whole tree

| Directory | Owns | Read before touching |
|---|---|---|
| `tofu/` | Proxmox VM/infrastructure resources (OpenTofu) | `docs/architecture/infrastructure.md`, `docs/proxmox/installation.md` |
| `ansible/` | Proxmox host config, guest OS config, Kubernetes bootstrap | `docs/architecture/infrastructure.md`, `docs/proxmox/installation.md` |
| `kubernetes/` | Cluster bootstrap, platform, and app manifests | `docs/architecture/kubernetes.md`, `docs/architecture/gitops.md` |
| `docs/` | All narrative documentation, ADRs, runbooks | `docs/README.md` (navigation index) |
| `.claude/` | Claude Code agents/skills/hooks | this file |
| `.github/workflows/` | CI (validation + security scanning only) | `docs/security/self-hosted-runners.md` |

Do not read every file in `docs/` for a routine task — use
`docs/README.md` to find the one or two relevant documents.

## Public-by-default rule

**This repository is, or is intended to become, public on GitHub. Assume
every file you write will be read by strangers.** Before committing
anything, consider whether it reveals: credentials, the real home network
topology (ISP, public IP, DDNS hostname, router make/model, real LAN CIDR,
MAC addresses, hardware serials), personal information beyond public
authorship, or internal identifiers with no documentation value. When
uncertain, use a `*.example` file with placeholder values instead of a real
one. Full policy: `docs/security/public-repository.md`.

## Secrets

Never commit: passwords, API tokens (GitHub, Proxmox), Tailscale auth keys,
SSH/age/TLS private keys, kubeconfigs with credentials, service-account
tokens, Ansible Vault passwords, OpenTofu state or plan files, `.env` files
with real values. Encrypted secrets are not automatically safe in a public
repo — SOPS+age usage requires the public-repo threat model reviewed in
`docs/security/public-repository.md` before it's treated as a committed
pattern. Real values live in GitHub Actions Secrets, local files covered by
`.gitignore`, or a vault — never in Git, plaintext or encrypted-by-default.

## Destructive-action policy

Stop and get explicit human approval before any of: `tofu apply` /
`tofu destroy`, `kubectl apply`/`delete` against a real cluster,
`kubeadm reset`, deleting a namespace holding state, deleting a PVC,
formatting a disk, destroying a VM, changing the Proxmox management
network or its firewall, modifying remote-access (Tailscale/SSH) rules,
rotating credentials, force-pushing, rewriting Git history, or resetting
any infrastructure state. Before asking, state: the action, its impact,
the rollback path, and expected downtime. Hooks in this repo block the
highest-risk command patterns automatically (see `.claude/hooks/`) — a
block is a prompt to have that conversation, not a bug to route around.

## Validation expectations

Run the gate for whatever you changed, don't assume it passes:

| Changed | Command |
|---|---|
| `tofu/**/*.tf` | `tofu fmt -check -recursive && tofu validate` (in the module dir) |
| `ansible/**` | `ansible-lint` and `ansible-playbook --syntax-check` |
| `kubernetes/**/*.yaml` | `yamllint .` and `kubeconform -strict` |
| `**/*.sh` | `shellcheck` |
| any | `gitleaks protect --staged` before commit |

`make validate` runs change-aware checks locally (see `Makefile`). Full
detail and rationale: `.claude/skills/validate-changes/SKILL.md`.

## Definition of Done

A change is done only when, as applicable to its type: it's formatted,
statically validated, security-scanned, documented (doc/ADR/STATUS.md
updated if the change is architectural or changes user-facing behavior),
and — only for infrastructure changes — actually applied and verified
against a real environment. Writing files is not "done."

## Claim vocabulary — say exactly what happened

- **"Generated"** — file written, nothing executed against it.
- **"Statically validated"** — a linter/formatter/validator ran and passed
  (name the tool). Does not mean it works at runtime.
- **"Tested"** — an automated test executed and passed. State which.
- **"Deployed"** — applied to the actual homelab (VM or cluster), state
  which environment.
- **"Verified"** — deployed *and* its behavior was directly observed
  (command output, dashboard, log) after applying. State how.

Never say "working" or "done" unless "verified" is also true. If something
is untested, say so plainly rather than implying otherwise.

## Git policy

Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
`chore:`, `security:`). Focused commits over sprawling ones. Agents must
not push, merge, force-push, or rewrite shared history without an explicit
instruction in that turn — prior approval for a similar action does not
carry forward.

## Documentation requirements

Architectural or behavior-changing work updates the relevant
`docs/architecture/*.md` and, if it's a real decision (not an obvious
implementation detail), an ADR (`.claude/skills/create-adr/`). Update
`STATUS.md` when something moves between PLANNED/IMPLEMENTED/VALIDATED/DEPLOYED.
Don't duplicate explanations already written elsewhere — link to them.
