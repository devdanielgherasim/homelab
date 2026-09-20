# 0016. Platform bootstrap with OpenTofu, not by hand

Status: Accepted
Date: 2026-09-20

## Context

ADR-0014 puts everything that runs on the cluster under Argo CD, except what Argo CD
needs in order to exist: the CNI (Cilium), Argo CD itself, its projects and root
Application, and the few Secrets that cannot be in a public repository. Those were
installed with `helm` and `kubectl` typed by an operator, and the Grafana admin Secret
and the `monitoring` namespace were created the same way. Nothing in Git could rebuild
them: a cluster rebuilt from the repository would come up without a CNI and without a
GitOps controller, and the steps to fix that lived in READMEs and in a shell history.

The requirement is that the whole environment is reproducible from zero, from Git, with no
manual step.

## Decision

Add a second OpenTofu stage, `tofu/environments/platform`, that runs after Ansible has
built the cluster and produces everything the GitOps controller depends on:

- **Cilium** as a `helm_release`, with the values file that is already in
  `kubernetes/bootstrap/cilium/`. The API server address is a private variable.
- **Argo CD** as a `helm_release` from the same values file the self-managing Application
  uses; the chart version is read from `kubernetes/platform/apps/argocd.yaml`, so there is
  one place to change it. The admin password is generated (`random_password`) and stored
  as a bcrypt hash; the initial admin Secret is never created.
- **AppProjects and the root Application** from the YAML files that are in Git
  (`kubectl_manifest`, which does not need the CRDs at plan time).
- **The LoadBalancer pool** (real LAN addresses) from a private, gitignored variable file,
  replacing the Ansible role that did the same.
- **Namespaces that need a Secret before Argo CD syncs them, and those Secrets**
  (`monitoring`, `grafana-admin`), generated with `random_password`.

State holds the generated passwords, so it is encrypted with OpenTofu's native state
encryption; the passphrase comes from the environment (`TF_ENCRYPTION`), never from the
repository. State stays local and gitignored, like the first stage.

Everything else stays with Argo CD. The Ansible stage keeps building the nodes and
kubeadm, and gains a playbook that fetches the kubeconfig to a private local path, so no
one copies it by hand. The chain is: `tofu` (VMs), Ansible (kubeadm), `tofu` (platform),
Argo CD.

## Alternatives considered

- **Ansible for the platform bootstrap too.** One tool fewer, but `helm_release` gives
  plan, diff and import for free, and the owner asked for OpenTofu. Ansible remains the
  right tool for the nodes.
- **Argo CD installs itself (`argocd-autopilot` or a kustomize `kubectl apply`).** Still a
  manual command, and it leaves the Secrets and the CNI out.
- **SOPS + age for the generated Secrets.** Encrypted secrets in Git are still planned for
  the workloads that need a value chosen by a person. For passwords nobody has to know in
  advance, generating them at bootstrap needs no key management and leaves nothing in Git.
- **The `kubernetes_manifest` resource for the Argo CD objects.** It needs the CRD to exist
  when the plan is made, which is not true on a fresh cluster. `kubectl_manifest` from the
  `alekc/kubectl` provider has no such need; the trade-off is a community provider.

## Consequences

The bootstrap is reviewable (`tofu plan`), repeatable and importable, and the manual steps
in the READMEs disappear. The running cluster was adopted with `import` blocks, not rebuilt
(2026-09-20: 10 objects imported, 2 generated passwords added, nothing destroyed; the Cilium
and Argo CD Helm releases went to revisions 4 and 2 with unchanged values and no agent
restart). The adoption rotated the Argo CD admin password and replaced the Grafana Secret's
password. The `import` file was removed afterwards, because an `import` block for an object
that does not exist fails and would break a bootstrap from zero.

Costs: a second state file to protect and back up (encrypted, but the passphrase must
be stored somewhere safe outside the repository); Cilium is now changed through a tofu
apply, which is the one place where a bad plan can cut the cluster's network, so its plan
is read before every apply; the Argo CD chart is installed by two systems (tofu at
bootstrap, Argo CD afterwards), which is safe only because both read the same values file
and version. Whether the rebuild really works is proved by rebuilding the cluster, not by
reading the code (plan task P8 in `plans/2026-09-19-professionalize-repo.md`).

## Result of the rebuild from zero (2026-09-20)

Accepted after the cluster was rebuilt from the repository (procedure and timings in
[`../runbooks/rebuild-cluster.md`](../runbooks/rebuild-cluster.md)). The three cluster VMs
were replaced, and Ansible plus the platform stage plus Argo CD brought back a cluster identical
to the one before: the same 3 nodes, 12 Applications `Synced/Healthy`, pods per namespace and
Helm charts. The platform stage planned `12 to add` on an empty state, applied in 2 minutes and
was idempotent afterwards; Argo CD converged in 4 minutes. What the rebuild found, and what was
done about it:

- The base image has no guest agent, and the provider waited 15 minutes per VM for it.
  `agent.timeout` in the VM module is now one minute.
- `ansible.cfg` keeps host key checking on, and a new VM has a new key. `scripts/bootstrap.sh`
  now forgets the old key of the VMs a plan creates and accepts an unknown key on first
  contact; a rebuild done with a manual `-replace` has to do it by hand (runbook, step 5).
- The script's own checks caught two mistakes of mine before they did harm (a plan-summary
  guard with the wrong expected text, and an exported state passphrase that broke the
  inventory); both are fixed.

Not proven: bare-metal Proxmox, restoring a live cluster from an etcd snapshot, and the `vms`
stage of the script end to end (the VMs were replaced by hand).
