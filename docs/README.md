# Documentation Index

Find the doc for your task instead of reading everything in `docs/`.

| I need to... | Read |
|---|---|
| Understand the overall design | [`architecture/overview.md`](architecture/overview.md) |
| Know what's manual vs. Ansible vs. OpenTofu vs. Argo CD | [`proxmox/installation.md`](proxmox/installation.md) (responsibility model) |
| Work on IP addressing, VPN, trust boundaries | [`architecture/networking.md`](architecture/networking.md) |
| Work on Proxmox, VMs, OpenTofu/Ansible | [`architecture/infrastructure.md`](architecture/infrastructure.md) |
| Work on kubeadm, Cilium, cluster internals | [`architecture/kubernetes.md`](architecture/kubernetes.md) |
| Work on Argo CD, delivery pipeline | [`architecture/gitops.md`](architecture/gitops.md) |
| Work on Prometheus/Grafana/Loki/Tempo | [`architecture/observability.md`](architecture/observability.md) |
| Understand what secrets/exposure rules apply | [`security/public-repository.md`](security/public-repository.md) |
| See how hardened the cluster is (CIS benchmark) | [`security/cis-benchmark.md`](security/cis-benchmark.md) |
| Configure or touch the self-hosted runner | [`security/self-hosted-runners.md`](security/self-hosted-runners.md) |
| Understand why a decision was made | [`adr/README.md`](adr/README.md) |
| Diagnose a known failure mode | [`troubleshooting/README.md`](troubleshooting/README.md) |
| Follow an operational procedure | [`runbooks/README.md`](runbooks/README.md) |
| Set up a dev environment / contribute | [`contributing/development-workflow.md`](contributing/development-workflow.md) |
| Use ChatGPT/Perplexity productively on this repo | [`contributing/ai-collaboration.md`](contributing/ai-collaboration.md) |

Authority order for conflicting information: repo code → `adr/` → these
docs → `AGENTS.md`/`CLAUDE.md` → agent/skill prompts.
