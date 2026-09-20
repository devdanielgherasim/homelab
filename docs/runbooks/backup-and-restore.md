# Backup and restore

What is backed up, and how each restore path was actually exercised. Scope and
the decision to keep everything on the Proxmox host are in
[ADR-0012](../adr/0012-local-backups.md).

| What | How | Where | Retention |
|---|---|---|---|
| etcd data, cluster PKI and the Secret-encryption key | `etcd-snapshot.timer` on `cp01` (`ansible/roles/etcd_backup`) | `/var/backups/etcd` on `cp01`, mode 600 | 7 copies, daily 02:30 UTC |
| `cp01` as a whole VM | Proxmox job `homelab-daily` (`ansible/roles/proxmox_backup`) | `local` storage of the Proxmox host | 3 copies, daily 03:30 |

The `pki-*.tar.gz` archive next to each snapshot holds `pki/` and `enc/` (the key
that encrypts Secrets). A restored snapshot cannot be read without `enc/`.

Workers and `vpn01` are not backed up: they hold no state and are rebuilt from
Git.

## Check that backups are healthy

Preconditions: SSH access to `cp01` and to the Proxmox host.

1. On `cp01`, confirm the timer is scheduled and the last run succeeded:

   ```bash
   systemctl list-timers etcd-snapshot.timer --no-pager
   sudo journalctl -u etcd-snapshot.service -n 5 --no-pager
   sudo ls -la /var/backups/etcd
   ```

2. Read the newest snapshot back. This is the same check the job runs before
   it keeps a file:

   ```bash
   sudo etcdutl snapshot status "$(sudo bash -c 'ls -1t /var/backups/etcd/etcd-*.db | head -1')" --write-out=table
   ```

3. On the Proxmox host, confirm a recent archive exists and the storage has room:

   ```bash
   ls -la /var/lib/vz/dump | grep vzdump-qemu-102
   pvesm status --storage local
   ```

Verification: the snapshot reports a revision and a key count, the newest
`vzdump-qemu-102-*.vma.zst` is from the last night, and `local` has free space.
Reference values from the first run (2026-09-19): 373 keys, revision 34688,
9.4 MB per snapshot; a 2.13 GB `vzdump` archive that took 50 s.

## Restore drill: etcd snapshot into a scratch directory

Proves a snapshot is restorable without touching the live cluster. Exercised on
2026-09-19.

1. Restore into a scratch directory on `cp01`:

   ```bash
   sudo etcdutl snapshot restore /var/backups/etcd/etcd-<stamp>.db --data-dir /tmp/etcd-restore-test
   ```

2. Compare the restored database with the snapshot:

   ```bash
   sudo etcdutl snapshot status /tmp/etcd-restore-test/member/snap/db --write-out=table
   ```

3. Remove the scratch directory: `sudo rm -rf /tmp/etcd-restore-test`.

Verification: the restored database has the same revision and key count as the
snapshot (34688 revisions, 373 keys on 2026-09-19). Rollback: none needed;
nothing live was changed. Downtime: none.

## Restore drill: `cp01` from a `vzdump` archive into a throwaway VM

Proves the VM backup boots and holds the cluster's data. The copy is created
**without a network interface**, because it would otherwise come up with the
same static address as the real `cp01`. Exercised on 2026-09-19.

1. On the Proxmox host, restore to an unused VMID:

   ```bash
   qmrestore /var/lib/vz/dump/vzdump-qemu-102-<stamp>.vma.zst 9100 --storage local-lvm --unique 1
   qm set 9100 --delete net0
   qm set 9100 --name cp01-restore-test --onboot 0
   qm start 9100
   ```

2. Wait for the guest agent (about 80 s), then check the contents:

   ```bash
   qm agent 9100 ping
   qm guest exec 9100 -- /usr/bin/test -e /etc/kubernetes/admin.conf
   qm guest exec 9100 -- /usr/bin/test -e /var/lib/etcd/member
   ```

3. Shut it down: `qm shutdown 9100`. Delete it when finished:
   `qm destroy 9100 --purge` (this permanently removes the VM and its disk;
   check the VMID first).

Verification: the restore takes under a minute (48 s), the VM boots, the guest
agent answers, `/etc/kubernetes/admin.conf`, the PKI, the etcd static pod
manifest, `/var/lib/etcd/member` and `/var/backups/etcd` are all present, and
the VM sees only the loopback interface. The backup log also shows the agent
freezing and thawing the file system, so archives are file-system consistent.
Downtime: none for the real cluster.

## Not yet exercised

Recovering the **live** cluster from an etcd snapshot (replacing the data of the
running control plane, or rebuilding a lost `cp01`) has **not** been tried. It
is deliberately absent here: a procedure written before it has been run once is
a guess. It needs a maintenance window and a plan for a control plane that is
briefly offline; when it is done once, it belongs in this file. Until then the
two drills above show that the snapshot is valid and that the whole VM can be
brought back.

Rebuilding the cluster from Git without any restore **has** been exercised: see
[`rebuild-cluster.md`](rebuild-cluster.md). It recreates the cluster; it does not bring back
its old state.

Also not covered by any backup: the OpenTofu state file (local and gitignored),
and all data on the Proxmox host outside the VM archives.
