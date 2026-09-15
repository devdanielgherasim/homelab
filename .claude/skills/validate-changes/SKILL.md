---
name: validate-changes
description: >
  Run the correct validation gate for whatever files just changed in this
  repository (OpenTofu, Ansible, Kubernetes manifests, shell, docs) instead
  of guessing which linter applies or running everything. Use before a
  commit, before claiming validation passed, or whenever AGENTS.md's
  validation table needs to actually be executed rather than cited.
---

# validate-changes

## Input

A set of changed file paths (from `git diff`, a PR, or a specific list).
If none given, derive it: `git diff --name-only --diff-filter=ACMR origin/main...HEAD`.

## Routing (matches AGENTS.md's validation table)

| Path pattern | Command |
|---|---|
| `tofu/**/*.tf` | `cd <module dir> && tofu fmt -check && tofu init -backend=false && tofu validate` |
| `ansible/**` | `ansible-lint` and `ansible-playbook --syntax-check` on touched playbooks |
| `kubernetes/**/*.yaml` | `yamllint -c .yamllint.yaml <files>` then `kubeconform -strict <files>` |
| `**/*.sh` | `shellcheck <files>` |
| `**/*.md` | `markdownlint -c .markdownlint.jsonc <files>` (if installed — optional) |
| any | `gitleaks detect --source . -v` before commit |

`make validate` (see `Makefile`) implements this exact routing — prefer
calling it over reimplementing the logic ad hoc, so there's one place this
lives.

## Output

Pass/fail per tool per file group, using the claim vocabulary from
`AGENTS.md` — "statically validated," not "tested" or "working," unless
something was actually executed at runtime. If a tool isn't installed,
say so explicitly (don't silently skip and imply it passed) — point at
`scripts/doctor.sh`.

## When this isn't enough

This skill covers static validation only. It does not deploy, apply, or
otherwise touch real infrastructure — that always requires the explicit
human approval described in `AGENTS.md`'s destructive-action policy,
regardless of how clean validation comes back.
