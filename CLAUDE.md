# CLAUDE.md

**`AGENTS.md` is the normative source for project rules — read it first.**
This file only adds Claude Code-specific routing on top of it.

## Repo map — navigate, don't sweep

Full map and ownership: `AGENTS.md`. Documentation index (task → doc to
read): `docs/README.md`. Do not read all of `docs/` for a routine task.

## Agents — when to delegate

| Task | Agent |
|---|---|
| Reviewing another agent's output, checking a diff for public-repo/security issues | `reviewer` |
| Current versions, deprecations, EOL, "what does the docs say" | `researcher` |
| Running lint/validate on changed files, want a compact pass/fail | `validator` |
| Writing/updating ADRs, runbooks, `STATUS.md`, architecture docs | `docs-writer` |

Prefer these over inline work when the task matches — see
`superpowers:prefer-subagents`. Don't spawn an agent for a one-line edit.

## Skills

`validate-changes`, `create-adr`, `security-review`, `write-runbook`,
`research-brief` — see `.claude/skills/*/SKILL.md`. Invoke explicitly by
name or via `/validate`, `/adr` (see `.claude/commands/`).

## Hooks (already active, see `.claude/hooks/`)

- `PreToolUse` on `Bash` blocks destructive infra commands (`tofu apply`,
  `kubectl delete`, `kubeadm reset`, force-push, etc.) — see `AGENTS.md`
  destructive-action policy. A block means: stop, explain, ask.
- `PostToolUse` on `Write`/`Edit` runs a secret scan plus the matching
  formatter/linter on the single file just touched. It never runs a full
  repo sweep.
- `SessionStart` prints a short status brief, not project history.

## Execution environment note

Ansible and `make` do not run natively on Windows. Repository automation
(`Makefile`, `ansible/`) targets **WSL2 Ubuntu** — see `docs/contributing/development-workflow.md`.
`kubectl`, `helm`, `tofu`, `git`, `gh` work fine from native PowerShell/Bash.

## Context discipline

This is a documentation- and IaC-heavy repo. Prefer grep/glob over reading
whole directories. `docs/architecture/*.md` are the single source of truth
per domain — don't re-derive networking/security facts from scratch when a
doc already states them; read and cite it instead.
