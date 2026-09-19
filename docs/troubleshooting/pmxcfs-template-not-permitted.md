# Ansible `template` cannot write the Proxmox firewall file

## Symptom

The `firewall_rules` stage of `proxmox_bootstrap` failed on the first real
run:

```text
[Errno 1] Operation not permitted
```

when rendering `/etc/pve/nodes/<node>/host.fw`.

## Diagnosis

The file was being written by `ansible.builtin.template`. The same task
works for ordinary files, so the target path was the difference:
`/etc/pve` is not a normal directory.

## Root cause

`/etc/pve` is `pmxcfs`, Proxmox's cluster filesystem, a FUSE filesystem with
non-POSIX semantics. `ansible.builtin.template` writes atomically using
`rename()` followed by `chmod()`, and pmxcfs rejects both. This is a known
Ansible/Proxmox interaction (ansible/ansible issue 70535).

## Fix

Render the template to `/tmp` first, then copy it into place with a plain
`cp`, which performs a direct open and write that pmxcfs accepts. Applied to
`firewall_rules.yml` and `firewall_enforce.yml`. Both stages then ran cleanly
and the host stayed reachable after `policy_in: DROP`.

## Prevention

- Both task files carry a comment explaining why the two-step copy exists,
  so it is not "simplified" back into a single `template` task.
- The config is syntax-checked with `pve-firewall compile` before it is
  enforced.
