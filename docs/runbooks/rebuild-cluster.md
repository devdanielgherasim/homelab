# Rebuild the cluster from Git

Replaces the three cluster VMs (`cp01`, `worker01`, `worker02`) with fresh ones and brings
the platform back from the repository: nodes, kubeadm, Cilium, Argo CD, and everything Argo
CD installs. Nothing is restored from a backup; the point is that nothing needs to be.
Exercised on 2026-09-20 on the running cluster ([ADR-0016](../adr/0016-platform-bootstrap-with-opentofu.md)).

`vpn01` and the Proxmox host are not touched. Bare-metal Proxmox (installation, template,
API token) is out of scope: see [`../proxmox/installation.md`](../proxmox/installation.md).

## Preconditions

- The repository is on the commit that is on `main`: Argo CD reads Git, not your disk.
- Private inputs exist: `tofu/environments/homelab/terraform.tfvars`,
  `tofu/environments/platform/terraform.tfvars`, the state passphrase (`TF_ENCRYPTION`), the
  admin SSH key, a Proxmox API token (or a temporary one, below).
- **Backups first** (they are the rollback, see below): a fresh etcd snapshot
  (`sudo systemctl start etcd-snapshot.service` on `cp01`), a `vzdump` of `cp01`
  (`vzdump 102 --storage local --mode snapshot --compress zstd` on the Proxmox host), and a
  copy of the snapshot, the PKI archive and both OpenTofu states **off the Proxmox host**.
  The PKI archive holds the cluster CA and the Secret-encryption key: keep the copy private.
- A baseline to compare with: `kubectl get nodes`, `kubectl -n argocd get applications`,
  pods per namespace, `helm ls -A`.

## Steps

1. **Token.** Use the normal Proxmox token, or create a temporary user and token with the
   same least-privilege grants (role `HomelabTofu` on `/pool/homelab`, `PVEDatastoreUser` on
   `/storage/local-lvm`, `PVESDNUser` on `/sdn/zones/localnetwork`) and remove them at the end.
2. **Protection off**, on these three VMs only. Proxmox refuses to delete a protected VM,
   which is what stops an accidental destroy:

   ```bash
   # on the Proxmox host
   qm config 102 | grep ^name   # check each VMID/name pair first: cp01, worker01, worker02
   qm set 102 --protection 0; qm set 103 --protection 0; qm set 104 --protection 0
   ```

3. **Start the platform stage from nothing.** Move
   `tofu/environments/platform/terraform.tfstate*` aside (`*.pre-rebuild`). Its content
   describes the old cluster; a fresh state also generates new passwords.
4. **Replace the VMs**, and read the plan first. It must be exactly three replacements:

   ```bash
   cd tofu/environments/homelab
   tofu plan -out=rebuild.plan \
     -replace='module.cp01.proxmox_virtual_environment_vm.this' \
     -replace='module.workers["worker01"].proxmox_virtual_environment_vm.this' \
     -replace='module.workers["worker02"].proxmox_virtual_environment_vm.this'
   # expect: three lines "will be replaced, as requested" and
   # "Plan: 3 to add, 0 to change, 3 to destroy." (note the wording: not "must be replaced")
   ```

   Apply that plan. The new VMs are created with `protection` and `on_boot` on again, from
   the code. Creation used to take 15 minutes per VM (the image has no guest agent yet and
   the provider waited for it); `agent.timeout` is now one minute.
5. **Forget the old SSH host keys** of the three VMs (`ssh-keygen -R <address>`), because
   `ansible.cfg` keeps host key checking on and the new VMs have new keys.
   `scripts/bootstrap.sh` does this by itself when the same run creates the VMs; a manual
   `-replace` does not go through it.
6. **Ansible and the platform stage**, through the entry point:

   ```bash
   make bootstrap STAGES="guests cluster host kubeconfig"
   make bootstrap STAGES="platform"      # shows the plan; expect "12 to add, 0 to change, 0 to destroy"
   ```

   The nodes are `NotReady` after `cluster` until Cilium is installed by `platform`.
7. **Wait for Argo CD** to converge: all Applications `Synced/Healthy` (12 on 2026-09-20).
8. **Remove the temporary token and user**, if one was made.
9. **Point other tools at the new cluster.** The kubeconfig in WSL is refreshed by the
   `kubeconfig` stage. Copies elsewhere (a Windows kubeconfig, Lens) still hold the old CA
   and must be replaced.

## Verification

- Same nodes, Applications, pod counts per namespace and Helm charts as the baseline.
- Gateway through its LoadBalancer address: about 90/10 between the two demo versions.
- Plain traffic from a pod outside the mesh to the demo Service is reset (STRICT mTLS).
- Prometheus: all active targets `up`; Grafana `/api/health` ok.
- Admin passwords: `tofu output -raw argocd_admin_password` logs in to Argo CD (HTTP 200);
  `argocd-initial-admin-secret` does not exist.
- `tofu plan` of the platform stage: `No changes`.
- On the Proxmox host: `protection: 1`, `onboot: 1` and the `startup` order on all four VMs.

## Measured on 2026-09-20

| Step | Time |
|---|---|
| Replace the three VMs (`tofu apply`) | 15 min 37 s (agent wait, now one minute) |
| Ansible: guests, cluster, host, kubeconfig | 3 min 11 s |
| Platform stage (Cilium, Argo CD, secrets) | 2 min 19 s |
| Argo CD to 12/12 `Synced/Healthy` | 4 min 4 s |

The cluster was unavailable for about 27 minutes in total. Lost: only ephemeral data
(Prometheus metrics live in an `emptyDir`). Changed: every generated password, the cluster
CA, the kubeconfig.

## Rollback

If the rebuild fails midway, `vpn01` and Proxmox are unaffected, and the workers hold no state.
The control plane can be brought back from the backups taken in the preconditions: restore
`cp01` from the `vzdump` archive (`qmrestore`, as in the drill in
[`backup-and-restore.md`](backup-and-restore.md)) and recreate the workers with OpenTofu.
That path was **not** needed and not exercised for a live cluster; only the isolated restore
drill was. Deleting the old copies afterwards is part of finishing: they hold the previous
cluster's CA and Secret-encryption key.

## What this did not prove

- Bare-metal Proxmox from nothing (installation, template, API token).
- Restoring a live cluster from an etcd snapshot (see `backup-and-restore.md`).
- `vpn01` and Tailscale: they were left alone.
- `scripts/bootstrap.sh`'s `vms` stage end to end: the VMs were replaced with `-replace`
  by hand (steps 4 and 5); the other stages ran through the script.
