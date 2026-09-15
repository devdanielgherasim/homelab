# homelab

A production-style Kubernetes homelab, built on a single Proxmox host, as a
DevOps / Platform Engineering learning project and portfolio reference.

> **Status: repository bootstrap complete. No infrastructure is
> provisioned yet.** See [`STATUS.md`](STATUS.md) for the honest,
> component-by-component breakdown — this README describes the target
> architecture, not what's currently running.

## Why this exists

To build and operate, hands-on, the full stack a Platform Engineer is
expected to know — virtualization, upstream Kubernetes internals,
networking/service mesh, GitOps delivery, observability, and security —
on real (if small) hardware, at zero recurring cost, with everything
reproducible from this Git repository.

## Architecture

```mermaid
flowchart TB
    internet[Internet] --> router[Home router]
    router -. "no management ports forwarded" .-> proxmox

    subgraph proxmox[Proxmox VE — physical host, ~16 GB RAM]
        vpn01[vpn01<br/>Tailscale gateway]
        cp01[cp01<br/>control plane]
        worker01[worker01]
        worker02[worker02]
    end

    admin[Remote admin] -- Tailscale --> vpn01
    vpn01 --> cp01
    vpn01 --> worker01
    vpn01 --> worker02
    cp01 --- cilium[Cilium CNI]
    worker01 --- cilium
    worker02 --- cilium
    cilium --> istio[Istio + Gateway API]
    istio --> svc[Services]
```

Full design: [`docs/architecture/overview.md`](docs/architecture/overview.md)
and the rest of [`docs/architecture/`](docs/architecture/).

## Technology stack

| Layer | Tools |
|---|---|
| Virtualization | Proxmox VE, Ubuntu Server 24.04 LTS guests |
| IaC | OpenTofu, Ansible |
| Kubernetes | kubeadm, containerd |
| Networking | Cilium, Hubble, MetalLB |
| Traffic | Istio, Kubernetes Gateway API |
| GitOps | Argo CD |
| CI | GitHub Actions (GitHub-hosted for all public/untrusted validation) |
| Security | Tailscale, SSH Ed25519, SOPS + age (pending review), Kyverno, Trivy, gitleaks |
| Observability | Prometheus, Grafana, Loki, Tempo, Hubble |

Rationale for each major choice is recorded as an ADR — see
[`docs/adr/`](docs/adr/).

## Repository structure

```
├── AGENTS.md              # normative rules for any AI agent working here
├── CLAUDE.md               # Claude Code-specific routing on top of AGENTS.md
├── STATUS.md                # what's PLANNED / IMPLEMENTED / VALIDATED / DEPLOYED
├── Makefile                  # make help / doctor / fmt / lint / validate / security
├── mise.toml                  # pinned local tool versions
├── tofu/                       # Proxmox VM/infrastructure resources (OpenTofu)
├── ansible/                     # Proxmox host + guest OS + Kubernetes bootstrap
├── kubernetes/                   # bootstrap / platform / apps manifests (Argo CD-managed)
├── docs/
│   ├── architecture/               # design, one doc per domain
│   ├── proxmox/                     # manual-install doc + responsibility model
│   ├── security/                     # public-repo threat model, runner trust boundary
│   ├── adr/                           # architecture decision records
│   ├── runbooks/ troubleshooting/      # operational knowledge (from real incidents)
│   └── contributing/                    # dev workflow, AI-collaboration guide
├── .claude/                                # agents, skills, hooks (see below)
└── .github/                                 # CI, issue/PR templates
```

## Quick start (for contributors)

```bash
# Ansible and Makefile targets need WSL2/Linux/macOS — see
# docs/contributing/development-workflow.md
git clone https://github.com/devdanielgherasim/homelab.git
cd homelab
mise install       # pinned tool versions from mise.toml
make doctor         # reports what's present/missing — installs nothing
make validate         # change-aware static validation
```

No infrastructure step exists yet to run — see
[`docs/proxmox/installation.md`](docs/proxmox/installation.md) for the
current manual starting point and the planned recovery sequence.

## Current status

See [`STATUS.md`](STATUS.md) for the full table. Short version: the
**repository and its AI/CI tooling are bootstrapped**; **Proxmox VE is
installed** on the physical host at installer defaults; **nothing beyond
that has been provisioned**.

## Roadmap

9-phase build plan (Foundation → Remote access → Kubernetes bootstrap →
Cluster networking → Service exposure → GitOps → Security controls →
Observability → Automation) — see
[`docs/architecture/overview.md`](docs/architecture/overview.md#6-implementation-roadmap).
Next milestone: [`STATUS.md`](STATUS.md#next-milestone).

## Security philosophy

This repository is public — everything committed is written assuming it
will be read by strangers. Real credentials and real home-network identity
never get committed, encrypted or not, without a reviewed reason. A
self-hosted GitHub Actions runner inside the homelab is planned but is
treated as privileged infrastructure: untrusted PR code never reaches it.
Full policy: [`docs/security/public-repository.md`](docs/security/public-repository.md)
and [`docs/security/self-hosted-runners.md`](docs/security/self-hosted-runners.md).

## Automation philosophy

Git is the source of truth, not any AI conversation. Manual configuration
stops the moment automation can reach a target — see
[`docs/proxmox/installation.md`](docs/proxmox/installation.md) for exactly
where the manual/automated line sits. Destructive operations
(`tofu apply`/`destroy`, `kubectl apply`/`delete`, credential rotation,
etc.) always require explicit human approval — see
[`AGENTS.md`](AGENTS.md#destructive-action-policy).

## AI-assisted development

Built collaboratively with Claude Code, Codex, ChatGPT, and Perplexity —
see [`AGENTS.md`](AGENTS.md) (normative, provider-neutral rules),
[`CLAUDE.md`](CLAUDE.md) (Claude Code routing), and
[`docs/contributing/ai-collaboration.md`](docs/contributing/ai-collaboration.md)
(using ChatGPT/Perplexity without losing Git as source of truth).

## Documentation

Start at [`docs/README.md`](docs/README.md) — a task-to-document index,
not a directory to read end-to-end.

## License

[MIT](LICENSE)
