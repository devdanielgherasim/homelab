# `tofu apply` fails with 403 on `Pool.Allocate` after narrowing the token

## Symptom

After the OpenTofu token was reduced to a custom role on a resource pool, a
`tofu apply` that only added `pool_id`, `protection` and a boot order to the four
VMs failed on every VM:

```text
Error: while adding VM 102 to pool homelab: error updating pool: received an
HTTP 403 response - Reason: Permission check failed (/pool/homelab, Pool.Allocate)
```

`tofu plan` with the same token had shown a clean in-place update, and a
verification run had already succeeded. Nothing had been changed on the VMs.

## Diagnosis

The earlier verification created, configured and destroyed a throwaway VM
through the real API, but it only cloned *into* the pool. It never exercised the
call the provider makes for an existing VM that it believes is not in the pool:
`PUT /pools/<pool>` with the VM list, which needs the write privilege
`Pool.Allocate`. Reading the plan does not reveal that, because a plan is
computed from reads.

A second test with the pool's read privilege added showed why the provider took
that path: without `Pool.Audit` it cannot read which pool a VM belongs to, so the
pool always looks unset and is "added" on every apply.

## Root cause

Two gaps in the role's privileges, found one after the other:

1. **`Pool.Audit` missing.** The provider could not read pool membership, so it
   planned to add every VM to the pool (a write needing `Pool.Allocate`) even
   though they were already members.
2. **The `startup` attribute** (boot order) needs `Sys.Modify` on `/`, which is a
   node-wide privilege and far broader than the token should have. This one was
   caught by the second verification, before it could fail an apply.

## Fix

- `Pool.Audit` (read-only) was added to the `HomelabTofu` role. The plan then
  showed no pool change, and the write privilege was confirmed to still be
  denied.
- Boot order moved out of OpenTofu into `ansible/roles/proxmox_vm_startup`, which
  runs as root on the host; the module ignores drift on `startup`.
- The verification now also covers the exact updates an apply performs
  (`protection`, pool read) and the refusal of pool writes and of deleting a
  protected VM.

## Prevention

- Least privilege has to be verified by performing the **write paths** an apply
  uses, on a throwaway resource, not by reading a plan. A plan only proves the
  reads.
- Do not widen a token to make a specific attribute work; ask whether the
  attribute belongs in that tool at all. Here the setting was moved to the layer
  that owns host configuration.
- Keep the change small: the next apply changes one attribute per VM.
