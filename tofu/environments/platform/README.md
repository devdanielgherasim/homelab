# tofu/environments/platform

The second OpenTofu stage. It runs after Ansible has built the cluster and installs what the
GitOps controller depends on, so that nothing in the bootstrap is typed by hand
([ADR-0016](../../../docs/adr/0016-platform-bootstrap-with-opentofu.md)).

| Resource | File | What it does |
|---|---|---|
| Cilium | `cilium.tf` | `helm_release` with `kubernetes/bootstrap/cilium/values.yaml`; the API server address is a private variable. |
| LoadBalancer pool | `cilium.tf` | `CiliumLoadBalancerIPPool` from `lb_pool_blocks` (real LAN addresses, private). |
| Argo CD | `argocd.tf` | Namespace, `helm_release` with `kubernetes/bootstrap/argocd/values.yaml` at the chart version pinned in `kubernetes/platform/apps/argocd.yaml`, a generated admin password (bcrypt hash only), the AppProjects and the root Application from the YAML files in Git. |
| `monitoring` and its Secret | `secrets.tf` | Namespace with its Pod Security labels and the generated `grafana-admin` Secret, which must exist before Argo CD syncs the stack. |

From there Argo CD manages itself and everything under `kubernetes/platform/apps/`.

## Order of the whole chain

1. `tofu/environments/homelab`: the VMs.
2. `ansible/`: node preparation and kubeadm, then `playbooks/k8s-kubeconfig.yml`, which fetches
   the kubeconfig to a private local path.
3. This stage.

`make bootstrap` (`scripts/bootstrap.sh`) runs the chain in that order as named stages (`vms`,
`guests`, `cluster`, `host`, `kubeconfig`, `platform`; `vpn` is separate). Every `tofu apply`
shows its plan and asks first; `make bootstrap ARGS=--plan-only` stops after the plans, and
`make bootstrap STAGES="kubeconfig platform"` runs only those. The stages `kubeconfig` and
`platform` (plan only) have been run through it on the live cluster; running the whole chain
from nothing has not (plan task P8), so the order of the earlier stages is unproven.
`TF_ENCRYPTION` is kept out of the other stages by the script, because the VM state is not
encrypted and the Ansible inventory reads it.

## Prerequisites (all private, none in Git)

- **Kubeconfig** at `~/.kube/homelab.conf` (or `-var kubeconfig_path=...`).
- **`terraform.tfvars`**, from `terraform.tfvars.example`: the API server address and the LB pool.
- **State encryption.** The state holds the generated passwords, so it is encrypted. Put the
  HCL from `encryption.example` in `TF_ENCRYPTION`, with a long passphrase stored in a password
  manager: without it the state cannot be read. `enforced = true` refuses an unencrypted state.

Run it from Linux or WSL, not from a Windows shell that intercepts TLS.

```sh
cd tofu/environments/platform
tofu init
tofu plan          # read it: Cilium is the CNI, a bad change there cuts the cluster's network
tofu apply
```

Passwords: `tofu output -raw argocd_admin_password` and `tofu output -raw grafana_admin_password`.

## Adopting a cluster that was installed by hand

The running cluster was adopted on 2026-09-20 with `import` blocks (one per object this stage
owns, in an `imports.tf` that is in the history of commit `dbcebaa`): 10 objects imported, 2
generated passwords added, 10 in-place updates, nothing destroyed. The file was deleted
afterwards on purpose: OpenTofu fails when an `import` block points at an object that does not
exist, so keeping it would break the bootstrap of a fresh cluster. To adopt another cluster that
was installed by hand, restore that file from history for one apply.

## Two owners, one chart

Argo CD is installed here at bootstrap and then manages itself from
`kubernetes/platform/apps/argocd.yaml`. Both read the same values file and the same chart
version (this stage reads the version from that Application), so they cannot diverge. The
`argocd-secret` data is ignored by the Application (`ignoreDifferences`), which is what keeps
the generated admin password from being reset.

## Rollback

`tofu apply` of a previous commit re-applies the previous values; both Helm releases are
`atomic`, so a failed upgrade rolls itself back. The state file is the thing to protect: back it
up together with the passphrase (see the plan, task on the OpenTofu state).
