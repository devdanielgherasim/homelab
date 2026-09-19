# Guest agent enabled on the VM but not installed in the guest

## Symptom

- `tofu apply` finished with a warning about a timeout waiting for the QEMU
  agent to report the VM's IP address. SSH worked, so it was first judged
  cosmetic.
- `qm snapshot` printed `skipping guest filesystem freeze - agent configured
  but not running?`.
- The Proxmox UI showed no IP address for any VM.

## Diagnosis

Checked inside all four VMs: the virtio channel exists
(`/dev/virtio-ports/org.qemu.guest_agent.0`), but `dpkg -s qemu-guest-agent`
reports the package as not installed and `systemctl` has no such unit.

## Root cause

The VM template sets `agent: enabled=1`, which only exposes the channel to the
guest. The Ubuntu cloud image does not ship the `qemu-guest-agent` package,
contrary to a comment in the template role and the OpenTofu module that said it
did. Nothing answered on the channel.

## Fix

New role `ansible/roles/qemu_guest_agent` installs and starts the package on
all four VMs (`playbooks/guest-agent.yml`). Afterwards `qm agent <vmid> ping`
succeeds and each VM reports its address. The first `vzdump` after the fix logs
`issuing guest-agent 'fs-freeze'` and `'fs-thaw'`, so backups are
file-system consistent. The false comments were corrected.

## Prevention

- The failure had been written off as cosmetic; a warning that repeats on every
  apply is a symptom to explain, not to ignore.
- Snapshots and backups depend on the agent, so a backup drill now checks that
  the log shows the freeze and thaw.
- Follow-up: put the package into the template image (or cloud-init) so a new
  VM does not depend on running the role afterwards.
