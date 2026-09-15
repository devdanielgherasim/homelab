# Using ChatGPT / Perplexity on This Project

Claude Code and Codex read `AGENTS.md`/`CLAUDE.md` directly from this repo.
ChatGPT and Perplexity don't have repo access by default — this page is how
to use them productively without losing the Git repo as source of truth.

## The rule

**An answer from ChatGPT or Perplexity doesn't count until it lands in
Git** — as an ADR (`docs/adr/`), a doc update, or a code change reviewed
like any other. Don't let architectural reasoning live only in a chat
transcript. If a conversation produces a real decision, turn it into an
ADR via `.claude/skills/create-adr/SKILL.md` (or ask Claude/Codex to do it
from a summary of the chat).

## Context block to paste in

For a cold-start ChatGPT conversation about this project, paste:

```
Production-style Kubernetes homelab on a single Proxmox host (~16GB RAM):
vpn01 (Tailscale gateway), cp01 (control plane), worker01/worker02.
Upstream Kubernetes via kubeadm+containerd, Cilium CNI, Istio+Gateway API,
Argo CD GitOps, Prometheus/Grafana/Loki/Tempo, SOPS+age, Kyverno, Trivy.
Public GitHub repo — see docs/architecture/overview.md for full design and
docs/security/public-repository.md for the public-repo threat model.
```

## Perplexity — ecosystem research hand-off

Use Perplexity for: current tool versions, deprecations/EOL, "what's the
current recommended way to do X in Cilium/Istio/Argo CD." Ask it to cite
sources. Bring the answer back as either:

- an update to the relevant `docs/architecture/*.md` (cite the source in
  the commit message), or
- a new/updated ADR if it changes a prior decision.

Do not paste real network details, credentials, or anything covered by
[`../security/public-repository.md`](../security/public-repository.md)
into any external chat tool — the same public-by-default assumption
applies to what you type into a browser tab as to what you commit.

## ChatGPT — architecture/design review

Useful for a second opinion on a design before it becomes an ADR, or for
learning explanations. Same rule: if it changes what this repo does, write
it down here, not just in that chat's memory.
