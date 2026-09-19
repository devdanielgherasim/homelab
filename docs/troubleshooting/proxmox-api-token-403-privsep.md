# OpenTofu clone fails with 403 despite correct role on the user

## Symptom

`tofu apply` cloning the VM template failed three times in a row, each
time with a different `403 Permission check failed`:

1. `VM.Clone` on `/vms/9000`
2. `Datastore.AllocateSpace` on `/storage/local-lvm`
3. `SDN.Use` on `/sdn/zones/localnetwork/vmbr0`

## Diagnosis

Each error named the exact privilege and ACL path that was missing, so each
one was fixed and re-applied separately. The first one was surprising:
the role `PVEVMAdmin` had already been granted at `/` to the OpenTofu user,
yet the token was still refused.

## Root cause

Three independent gaps:

1. The API token was created with `--privsep 1`. With privilege separation
   a token's effective permissions are the **intersection** of the user's
   ACLs and the token's own ACLs, not the union. Granting the role only to
   the user left the token (`opentofu@pve!tofu`, the principal OpenTofu
   actually authenticates as) with an empty intersection.
2. `PVEVMAdmin` does not contain `Datastore.AllocateSpace`; storage
   permissions live in a separate ACL namespace (`/storage/<id>`).
3. Proxmox VE 9 checks `SDN.Use` even for the default Linux bridge, because
   `vmbr0` belongs to the built-in `localnetwork` SDN zone.

## Fix

In `ansible/roles/proxmox_bootstrap/tasks/api_token.yml`, grant every role
to **both** the user and the token, on three paths:

| Path | Role |
|---|---|
| `/` | `PVEVMAdmin` |
| `/storage/<datastore_id>` | `PVEDatastoreUser` |
| `/sdn/zones/<zone>` | `PVESDNUser` |

## Prevention

- The task file's header documents all three namespaces and the `privsep`
  intersection rule, so the next reader does not rediscover it.
- The provider's "kitchen sink" example role (about 40 privileges, labelled
  excessive by its own docs) was deliberately not adopted.
- Known follow-up: the `/` grant is broader than necessary. Narrowing it to
  a pool or `/vms` with a custom role is tracked in
  [`../../plans/2026-09-19-professionalize-repo.md`](../../plans/2026-09-19-professionalize-repo.md).
