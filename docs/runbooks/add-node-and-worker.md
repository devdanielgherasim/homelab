# Add a Proxmox node, add or move a worker

Adding a second machine as a standalone Proxmox node and placing workers on it
([ADR-0020](../adr/0020-second-standalone-proxmox-node.md)). Two commands do the work; the only
manual step is installing Proxmox VE from the ISO.

**What has been exercised, and what has not.** On 2026-09-20 the second node (`pve02`) was
bootstrapped and `worker02` was moved to it, stage by stage, with the same playbooks and the same
OpenTofu configuration that the scripts below chain together. `scripts/bootstrap.sh vms
--plan-only` was run for real on both hosts. The scripts `scripts/proxmox-node.sh` and
`scripts/worker.sh` themselves have **not** yet been run end to end: this page is their intended
use, and it is corrected the first time they are.

## Preconditions

- Proxmox VE 9 installed on the machine (ext4/LVM-thin on a small disk, not ZFS), hostname
  equal to the node name you will use (`pve02`), a static address on the management network.
  BIOS: Intel VT-x / AMD-V on.
- The admin SSH key exists (`~/.ssh/homelab_admin_ed25519`); the machine is reachable from where
  the scripts run.
- The primary node and the cluster are healthy; the repository's private files exist
  (`terraform.tfvars`, `ansible/inventories/production/hosts.yml`).

## Add a Proxmox node

```bash
scripts/proxmox-node.sh add pve02 <management-ip>
```

After one question it: installs the admin key (asking for the root password once, in your
terminal), adds the node to the inventory and to `proxmox_nodes`, runs the safe bootstrap stages
(network check, SSH key, firewall allow rules, CA bundle), builds VM template 9000 on it, and
checks TLS and that OpenTofu reaches it. It does not enforce the firewall or lock SSH down:
those stay a separate decision, run last and one at a time, with the console at hand.

Up to three extra nodes (the three provider slots of `proxmox_nodes`).

## Add a worker

```bash
scripts/worker.sh add worker03 [--node pve02] [--memory 5632] [--cores 3]
```

The VMID and address are the next free ones unless given. A capacity check compares the memory
of the VMs already on the node, plus the new one, with the host's memory minus about 1.7 GiB
(measured: Proxmox VE idles at about 1.5 GiB). Then: plan, one question, VM, guest preparation,
`kubeadm join`, a check that the node is `Ready`. Run it yourself in a terminal
(`!` in the assistant's prompt): the assistant's command guard stops it from running node
deletion and the apply.

## Move a worker to another node

```bash
scripts/worker.sh move worker02 --node pve02 [--destroy-old]
```

Same name, VMID and address. The Kubernetes node is drained and deleted (its pods reschedule; each
Deployment has one replica, so each is absent for a minute or two), the old VM is shut down
cleanly and left on the old host, stopped and protected, the VM is created on the new node and
joined. Without `--destroy-old` the old VM stays until you remove it yourself; the command prints how.

Before moving, check the other workers can hold the pods (2026-09-20: 872 MiB of requests moved
from `worker02` to `worker01`, which then used about 77% of its memory; nothing had to be scaled
down).

## Remove a worker

```bash
scripts/worker.sh remove worker03
```

Drain, delete the node, clear the VM's protection, destroy the VM.

## Verification

- `kubectl get nodes` shows the node `Ready`; `kubectl -n kube-system get pods -l k8s-app=cilium
  -o wide` has a Cilium pod on it; the kubelet serving certificate request is `Approved,Issued`
  (the approver does it).
- `qm list` on the node's Proxmox host shows the VM running, with the guest agent answering
  (`qm agent <vmid> ping`).
- The Argo CD Applications are `Synced/Healthy` and the Prometheus targets are up.

## Rollback

- A step that fails before the drain leaves `terraform.tfvars` as it was (the script restores it).
- After the drain: `kubectl uncordon <worker>` if the node was not deleted yet. For a move, the old
  VM is still on the old host; start it with `qm start <vmid>` and, since the Kubernetes node object
  was deleted, join it again with the same playbooks (`scripts/bootstrap.sh cluster`).
- A copy of every private file the scripts edit is kept in `~/.config/homelab/backups/`.

## Expected downtime

None for the cluster: the API and the other workers keep serving. Pods of the drained worker are
absent while they reschedule.
