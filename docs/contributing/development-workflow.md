# Development Workflow

## Prerequisites

Ansible and this repository's `Makefile` targets do not run natively on
Windows. Use **WSL2 (Ubuntu)** as the working environment for anything
beyond editing files and running `git`/`kubectl`/`helm`/`tofu`/`gh`
natively from Windows or PowerShell.

Inside WSL2:

```bash
# one-time: install mise (https://mise.jdx.dev) — do NOT use
# `sudo snap install mise`: it requires --classic confinement (unrestricted
# system access), unnecessary for a user-space tool install.
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# one-time: mise's pypi/pipx backend (used for yamllint) needs pipx or uv
# present first, or `mise install` fails on yamllint specifically
sudo apt update && sudo apt install -y pipx

# clone and enter the repo (or use the Windows-side clone via /mnt/e/...)
cd homelab

# install pinned tool versions declared in mise.toml
mise install

# check what's present, missing, or drifted — installs nothing
make doctor
```

`scripts/doctor.sh` is the source of truth for what `make doctor` checks;
it reports, it never installs.

## Fork and reproduce

This repository is designed so another engineer can fork it, supply their
own environment values, and reproduce the architecture — see
[`../proxmox/installation.md`](../proxmox/installation.md#reproducibility--disaster-recovery-objective)
for the full sequence. In short:

1. Fork/clone the repository.
2. Copy every `*.example` file to its real counterpart (`.env.example` →
   `.env`, `terraform.tfvars.example` → `terraform.tfvars`,
   `inventory.example.yaml` → real inventory) and fill in your own values
   — none of these real files are committed (see `.gitignore`).
3. Provide secrets via GitHub Actions Secrets (for CI) or local
   environment variables / Ansible Vault (for local runs) — never in Git.
4. Follow the phases in
   [`../architecture/overview.md`](../architecture/overview.md#6-implementation-roadmap).

## Everyday commands

| Command | Does |
|---|---|
| `make help` | List available targets |
| `make doctor` | Report tool presence/version drift, install nothing |
| `make fmt` | Format changed files (`tofu fmt`, etc.) |
| `make lint` | Lint changed files by domain |
| `make validate` | Static validation for changed files (see `AGENTS.md`) |
| `make security` | Local secret scan + IaC security scan |

Infrastructure-changing targets (`make infra-plan`, `make cluster`, etc.)
are intentionally **not implemented yet** — see `Makefile` and the
destructive-action policy in [`../../AGENTS.md`](../../AGENTS.md).

## Commit conventions

Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
`chore:`, `security:`). See [`../../AGENTS.md`](../../AGENTS.md#git-policy).

## Before opening a PR

1. `make validate` and `make security` pass locally.
2. Docs updated if the change is architectural (`docs/architecture/*`) or
   changes behavior described elsewhere.
3. `STATUS.md` updated if a component's state changed.
4. No `*.example`-worthy real values committed — see
   [`../security/public-repository.md`](../security/public-repository.md).

CI (`.github/workflows/validate.yml`, `security.yml`) re-runs all of this
on GitHub-hosted runners regardless.
