# `ssh_lockdown` used the public key as the private key

## Symptom

The `ssh_lockdown` stage of `proxmox_bootstrap` failed its independent
key-login check with an "unprotected private key file" / bad-permissions
style SSH error, not an obviously wrong path.

## Diagnosis

The permissions message pointed away from the real cause. Printing the
rendered command showed SSH was being given the `.pub` file as `-i`.

## Root cause

The private key path was derived from the public key path with
`regex_replace('\\.pub$', '')` inside a YAML `>-` folded block scalar. The
backslash escaping did not survive the YAML-then-Jinja round trip, so the
regex never matched and the `.pub` path passed through unchanged.

## Fix

Removed the derivation. `proxmox_bootstrap_admin_ssh_privkey_path` is now an
explicit variable next to `proxmox_bootstrap_admin_ssh_pubkey_path`. The
re-run passed the role's own key-login self-check before it touched
`sshd_config`.

## Prevention

- Two explicit variables instead of clever string derivation; the defaults
  file explains why.
- The safety design worked as intended: the stage re-verifies key login
  itself before disabling password authentication, so this bug could not lock
  out the host.
